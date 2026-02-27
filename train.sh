#!/usr/bin/env bash
# Usage: ./train.sh <rounds> <batch_size>
#
# Runs the training loop: discover skills, predict, evaluate, refine, metrics, commit, branch.

set -euo pipefail

ROUNDS=${1:-5}
BATCH_SIZE=${2:-10}
AGENT_CMD="${AGENT_CMD:-claude}"
REPO="vllm-project/vllm"
# By default no TTY (no stream/echo). Set AGENT_TTY=1 to stream output, skip permission check, exit when done.
AGENT_TTY="${AGENT_TTY:-0}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
# Show the command we're about to run (no execution)
show_cmd() { echo "[$(date '+%H:%M:%S')]   \$ $*"; }

run_agent() {
    local prompt_file=$1
    shift
    local subs=()
    while [[ $# -gt 0 ]]; do
        subs+=("$1")
        shift
    done
    local prompt
    prompt=$(cat "$prompt_file")
    for sub in "${subs[@]}"; do
        local key="${sub%%=*}"
        local val="${sub#*=}"
        prompt="${prompt//\{\{$key\}\}/$val}"
    done
    local tmp
    tmp=$(mktemp)
    printf '%s' "$prompt" > "$tmp"
    # AGENT_TTY=1: stream output, skip permission check, exit when done (claude: --dangerously-skip-permissions -p).
    # Default: -p with stdin (no stream/echo).
    if [[ "$AGENT_TTY" == "1" ]]; then
        if [[ "$AGENT_CMD" == "claude" ]]; then
            show_cmd "${AGENT_CMD} --dangerously-skip-permissions -p < <prompt_stdin> ${subs[*]}"
        else
            show_cmd "${AGENT_CMD} < <prompt_stdin> ${subs[*]}"
        fi
    else
        show_cmd "${AGENT_CMD} -p < <prompt_stdin> ${subs[*]}"
    fi
    local ret=0
    if [[ "$AGENT_CMD" == "agent" ]]; then
        $AGENT_CMD -p "$(cat "$tmp")" --trust || ret=$?
    elif [[ "$AGENT_TTY" == "1" ]] && [[ "$AGENT_CMD" == "claude" ]]; then
        $AGENT_CMD --dangerously-skip-permissions -p < "$tmp" || ret=$?
    elif [[ "$AGENT_TTY" == "1" ]]; then
        $AGENT_CMD < "$tmp" || ret=$?
    else
        $AGENT_CMD -p < "$tmp" || ret=$?
    fi
    rm -f "$tmp"
    return $ret
}

pick_discovery_batch() {
    python -u utils.py pick-batch --size "$BATCH_SIZE"
}

pick_prediction_batch() {
    python -u utils.py pick-batch --size "$BATCH_SIZE" --exclude-used
}

ensure_data() {
    local fetched
    fetched=$(find data/prs -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${fetched:-0}" -lt $((BATCH_SIZE * 3)) ]]; then
        log "Need more PR data ($fetched so far). Fetching random sample (streaming below)..."
        show_cmd "./fetch.sh --batch $((BATCH_SIZE * 5)) closed"
        ./fetch.sh --batch $((BATCH_SIZE * 5)) closed
    else
        log "PR data OK ($fetched PRs)."
    fi
}

run_round() {
    local round=$1
    log "════════ ROUND $round / $ROUNDS ════════"

    # Step 1: Skill discovery
    log "Step 1/5: Skill discovery..."
    show_cmd "python -u utils.py pick-batch --size $BATCH_SIZE"
    local discover_batch
    discover_batch=$(pick_discovery_batch)
    local pr_dirs
    pr_dirs=$(echo "$discover_batch" | xargs -I{} echo "data/prs/{}" | tr '\n' ' ')
    run_agent prompts/discover_skills.md "PR_DIRS=$pr_dirs"

    # Step 2: Predict outcomes for a different batch
    log "Step 2/5: Predicting outcomes..."
    show_cmd "python -u utils.py pick-batch --size $BATCH_SIZE --exclude-used"
    local predict_batch
    predict_batch=$(pick_prediction_batch)
    local num_pred total_pred
    total_pred=$(echo $predict_batch | wc -w | tr -d ' ')
    num_pred=0
    for pr in $predict_batch; do
        num_pred=$((num_pred + 1))
        log "  [${num_pred}/${total_pred}] Predicting PR #${pr}..."
        run_agent prompts/predict_review.md "PR_DIR=data/prs/${pr}" "PR_NUMBER=${pr}"
    done

    # Step 3: Evaluate predictions
    log "Step 3/5: Evaluating predictions..."
    num_pred=0
    for pr in $predict_batch; do
        num_pred=$((num_pred + 1))
        log "  [${num_pred}/${total_pred}] Evaluating PR #${pr}..."
        run_agent prompts/evaluate_prediction.md "PR_DIR=data/prs/${pr}" "PR_NUMBER=${pr}"
    done

    # Step 4: Refine skills
    log "Step 4/5: Refining skills..."
    local eval_files
    eval_files=$(echo "$predict_batch" | xargs -I{} echo "results/evaluations/{}.json" | tr '\n' ' ')
    run_agent prompts/refine_skills.md "EVAL_FILES=$eval_files"

    # Step 5: Compute metrics
    log "Step 5/5: Computing metrics..."
    show_cmd "python -u utils.py compute-metrics --round $round"
    python -u utils.py compute-metrics --round "$round"

    # Step 6: Git only on success — branch first, then commit (no commit/branch on failure)
    local metrics_file="results/metrics/round_${round}.json"
    local outcome_pct triage_pct total_skills
    if [[ -f "$metrics_file" ]]; then
        outcome_pct=$(python -c "import json; print(int(round(json.load(open('$metrics_file')).get('outcome_accuracy',0)*100)))")
        triage_pct=$(python -c "import json; print(int(round(json.load(open('$metrics_file')).get('triage_accuracy',0)*100)))")
        total_skills=$(python -c "import json; print(json.load(open('$metrics_file')).get('total_skills',0))")
    else
        outcome_pct=0
        triage_pct=0
        total_skills=0
    fi
    local commit_msg="training round $round: ${outcome_pct}% outcome, ${triage_pct}% triage, ${total_skills} skills"

    # Only branch and commit when round succeeded (metrics file exists and has no error)
    if [[ -f "$metrics_file" ]] && ! grep -q '"error"' "$metrics_file" 2>/dev/null; then
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            show_cmd "git branch training/round-$round && git add ... && git commit -m \"$commit_msg\""
            git branch "training/round-$round" 2>/dev/null || true
            git add skills/ results/
            git add -f results/predictions/*.json results/evaluations/*.json results/metrics/*.json results/skill_changelog.md 2>/dev/null || true
            git status --short skills/ results/ | grep -q . && git commit -m "$commit_msg" || true
        fi
    else
        log "Skipping git (round had errors or no metrics)."
    fi

    log "Round $round complete. Metrics:"
    [[ -f "$metrics_file" ]] && cat "$metrics_file" || echo "  (none)"
}

log "Starting training: $ROUNDS rounds, batch size $BATCH_SIZE"
ensure_data
mkdir -p results/predictions results/evaluations results/metrics results/reviews results/resolutions
mkdir -p skills

for (( r=1; r<=ROUNDS; r++ )); do
    run_round "$r"
    log ""
done

log "Training complete. Run ./evaluate.sh for holdout metrics."
log "Skills are in skills/. Review results/skill_changelog.md for evolution history."

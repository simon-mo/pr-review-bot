#!/usr/bin/env bash
# Usage: ./train.sh <rounds> <batch_size>
#
# Runs the training loop: discover skills, predict, evaluate, refine, metrics, commit, branch.

set -euo pipefail

ROUNDS=${1:-5}
BATCH_SIZE=${2:-10}
AGENT_CMD="${AGENT_CMD:-claude}"
REPO="vllm-project/vllm"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

run_agent() {
    local prompt_file=$1
    shift
    local prompt
    prompt=$(cat "$prompt_file")
    while [[ $# -gt 0 ]]; do
        local key="${1%%=*}"
        local val="${1#*=}"
        prompt="${prompt//\{\{$key\}\}/$val}"
        shift
    done
    echo "$prompt" | $AGENT_CMD -p
}

pick_discovery_batch() {
    python3 utils.py pick-batch --size "$BATCH_SIZE"
}

pick_prediction_batch() {
    python3 utils.py pick-batch --size "$BATCH_SIZE" --exclude-used
}

ensure_data() {
    local fetched
    fetched=$(find data/prs -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${fetched:-0}" -lt $((BATCH_SIZE * 3)) ]]; then
        log "Need more PR data. Fetching..."
        ./fetch.sh --batch $((BATCH_SIZE * 5)) closed
    fi
}

run_round() {
    local round=$1
    log "════════ ROUND $round ════════"

    # Step 1: Skill discovery
    log "Step 1: Skill discovery..."
    local discover_batch
    discover_batch=$(pick_discovery_batch)
    local pr_dirs
    pr_dirs=$(echo "$discover_batch" | xargs -I{} echo "data/prs/{}" | tr '\n' ' ')
    run_agent prompts/discover_skills.md "PR_DIRS=$pr_dirs"

    # Step 2: Predict outcomes for a different batch
    log "Step 2: Predicting outcomes..."
    local predict_batch
    predict_batch=$(pick_prediction_batch)

    for pr in $predict_batch; do
        log "  Predicting PR #${pr}..."
        run_agent prompts/predict_review.md "PR_DIR=data/prs/${pr}" "PR_NUMBER=${pr}"
    done

    # Step 3: Evaluate predictions
    log "Step 3: Evaluating predictions..."
    for pr in $predict_batch; do
        log "  Evaluating PR #${pr}..."
        run_agent prompts/evaluate_prediction.md "PR_DIR=data/prs/${pr}" "PR_NUMBER=${pr}"
    done

    # Step 4: Refine skills
    log "Step 4: Refining skills..."
    local eval_files
    eval_files=$(echo "$predict_batch" | xargs -I{} echo "results/evaluations/{}.json" | tr '\n' ' ')
    run_agent prompts/refine_skills.md "EVAL_FILES=$eval_files"

    # Step 5: Compute metrics
    log "Step 5: Computing metrics..."
    python3 utils.py compute-metrics --round "$round"

    # Step 6: Git commit and branch
    local metrics_file="results/metrics/round_${round}.json"
    local outcome_pct triage_pct total_skills
    if [[ -f "$metrics_file" ]]; then
        outcome_pct=$(python3 -c "import json; print(int(round(json.load(open('$metrics_file')).get('outcome_accuracy',0)*100)))")
        triage_pct=$(python3 -c "import json; print(int(round(json.load(open('$metrics_file')).get('triage_accuracy',0)*100)))")
        total_skills=$(python3 -c "import json; print(json.load(open('$metrics_file')).get('total_skills',0))")
    else
        outcome_pct=0
        triage_pct=0
        total_skills=0
    fi
    local commit_msg="training round $round: ${outcome_pct}% outcome, ${triage_pct}% triage, ${total_skills} skills"

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git add skills/ results/
        git add -f results/predictions/*.json results/evaluations/*.json results/metrics/*.json results/skill_changelog.md 2>/dev/null || true
        git status --short skills/ results/ | grep -q . && git commit -m "$commit_msg" || true
        git branch "training/round-$round" 2>/dev/null || true
    fi

    log "Round $round complete. Metrics:"
    cat "$metrics_file"
}

log "Starting training: $ROUNDS rounds, batch size $BATCH_SIZE"
ensure_data
mkdir -p results/predictions results/evaluations results/metrics results/reviews results/resolutions

for (( r=1; r<=ROUNDS; r++ )); do
    run_round "$r"
    log ""
done

log "Training complete. Run ./evaluate.sh for holdout metrics."
log "Skills are in skills/. Review results/skill_changelog.md for evolution history."

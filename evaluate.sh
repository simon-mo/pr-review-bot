#!/usr/bin/env bash
# Usage: ./evaluate.sh <holdout_size>
#
# Runs holdout evaluation: get holdout PRs, predict and evaluate each, compute metrics, commit results.

set -euo pipefail

SIZE=${1:?Usage: ./evaluate.sh <holdout_size>}
AGENT_CMD="${AGENT_CMD:-claude}"
AGENT_TTY="${AGENT_TTY:-0}"

echo "[$(date '+%H:%M:%S')] Running holdout evaluation on $SIZE PRs..."
echo "[$(date '+%H:%M:%S')]   \$ python -u utils.py get-holdout --size $SIZE"
HOLDOUT=$(python -u utils.py get-holdout --size "$SIZE")
total=$(echo "$HOLDOUT" | wc -w | tr -d ' ')
echo "[$(date '+%H:%M:%S')] Holdout set: $total PRs. Streaming progress below..."

run_prompt() {
    local prompt=$1
    local prompt_src=$2
    local pr_num=$3
    local tmp
    tmp=$(mktemp)
    printf '%s' "$prompt" > "$tmp"
    if [[ "$AGENT_TTY" == "1" ]]; then
        if [[ "$AGENT_CMD" == "claude" ]]; then
            echo "[$(date '+%H:%M:%S')]   \$ $AGENT_CMD --dangerously-skip-permissions -p <stdin> (from ${prompt_src}) PR_DIR=data/prs/${pr_num} PR_NUMBER=${pr_num}"
        else
            echo "[$(date '+%H:%M:%S')]   \$ $AGENT_CMD <stdin> (from ${prompt_src}) PR_DIR=data/prs/${pr_num} PR_NUMBER=${pr_num}"
        fi
    else
        echo "[$(date '+%H:%M:%S')]   \$ $AGENT_CMD -p <stdin> (from ${prompt_src}) PR_DIR=data/prs/${pr_num} PR_NUMBER=${pr_num}"
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

idx=0
for pr in $HOLDOUT; do
    idx=$((idx + 1))
    echo "  [${idx}/${total}] Evaluating PR #${pr} (predict + evaluate)..."
    run_prompt "$(sed "s|{{PR_DIR}}|data/prs/${pr}|g; s|{{PR_NUMBER}}|${pr}|g" prompts/predict_review.md)" "prompts/predict_review.md" "$pr"
    run_prompt "$(sed "s|{{PR_DIR}}|data/prs/${pr}|g; s|{{PR_NUMBER}}|${pr}|g" prompts/evaluate_prediction.md)" "prompts/evaluate_prediction.md" "$pr"
done

echo "[$(date '+%H:%M:%S')] Computing holdout metrics..."
echo "[$(date '+%H:%M:%S')]   \$ python -u utils.py compute-holdout-metrics"
python -u utils.py compute-holdout-metrics

echo ""
echo "Holdout evaluation complete. Results: results/metrics/holdout.json"
cat results/metrics/holdout.json

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[$(date '+%H:%M:%S')]   \$ git add results/... && git commit -m \"evaluate: holdout $SIZE PRs\""
    git add results/predictions results/evaluations results/metrics
    git diff --cached --quiet || git commit -m "evaluate: holdout $SIZE PRs"
fi

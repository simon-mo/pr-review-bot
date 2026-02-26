#!/usr/bin/env bash
# Usage: ./evaluate.sh <holdout_size>
#
# Runs holdout evaluation: get holdout PRs, predict and evaluate each, compute metrics, commit results.

set -euo pipefail

SIZE=${1:?Usage: ./evaluate.sh <holdout_size>}
AGENT_CMD="${AGENT_CMD:-claude}"

echo "[$(date '+%H:%M:%S')] Running holdout evaluation on $SIZE PRs..."
echo "[$(date '+%H:%M:%S')]   \$ python -u utils.py get-holdout --size $SIZE"
HOLDOUT=$(python -u utils.py get-holdout --size "$SIZE")
total=$(echo "$HOLDOUT" | wc -w | tr -d ' ')
echo "[$(date '+%H:%M:%S')] Holdout set: $total PRs. Streaming progress below..."

run_prompt() {
    local prompt=$1
    local prompt_src=$2
    local pr_num=$3
    echo "[$(date '+%H:%M:%S')]   \$ $AGENT_CMD -p < ${prompt_src} PR_DIR=data/prs/${pr_num} PR_NUMBER=${pr_num}"
    if [[ "$AGENT_CMD" == "agent" ]]; then
        local tmp
        tmp=$(mktemp)
        printf '%s' "$prompt" > "$tmp"
        $AGENT_CMD -p "$(cat "$tmp")" --trust
        rm -f "$tmp"
    else
        echo "$prompt" | $AGENT_CMD -p
    fi
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

#!/usr/bin/env bash
# Usage: ./evaluate.sh <holdout_size>
#
# Runs holdout evaluation: get holdout PRs, predict and evaluate each, compute metrics, commit results.

set -euo pipefail

SIZE=${1:?Usage: ./evaluate.sh <holdout_size>}
AGENT_CMD="${AGENT_CMD:-claude}"

echo "Running holdout evaluation on $SIZE PRs..."

HOLDOUT=$(python3 utils.py get-holdout --size "$SIZE")

for pr in $HOLDOUT; do
    echo "  Evaluating PR #${pr}..."
    sed "s|{{PR_DIR}}|data/prs/${pr}|g; s|{{PR_NUMBER}}|${pr}|g" prompts/predict_review.md | $AGENT_CMD -p
    sed "s|{{PR_DIR}}|data/prs/${pr}|g; s|{{PR_NUMBER}}|${pr}|g" prompts/evaluate_prediction.md | $AGENT_CMD -p
done

python3 utils.py compute-holdout-metrics

echo ""
echo "Holdout evaluation complete. Results: results/metrics/holdout.json"
cat results/metrics/holdout.json

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git add results/predictions results/evaluations results/metrics
    git diff --cached --quiet || git commit -m "evaluate: holdout $SIZE PRs"
fi

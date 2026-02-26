#!/usr/bin/env bash
# Usage: ./run.sh
#
# Full pipeline: fetch training data, train, evaluate, print summary, push if remote exists.

set -euo pipefail

echo "═══════════════════════════════════════════════════"
echo "  PR Review Bot — Full Pipeline"
echo "═══════════════════════════════════════════════════"
echo ""

echo "[$(date '+%H:%M:%S')] Step 1/3: Fetching PRs (random sample, streaming below)..."
./fetch.sh --batch 200 closed
echo ""
echo "[$(date '+%H:%M:%S')] Step 2/3: Training (streaming below)..."
./train.sh 10 15
echo ""
echo "[$(date '+%H:%M:%S')] Step 3/3: Holdout evaluation (streaming below)..."
./evaluate.sh 20

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Final Summary"
echo "═══════════════════════════════════════════════════"
echo "Skills discovered:"
ls -la skills/*.md 2>/dev/null || echo "  (none yet)"
echo ""
echo "Holdout metrics:"
cat results/metrics/holdout.json 2>/dev/null || echo "  (none)"
echo ""

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
    echo "Pushing commits to origin..."
    git push origin HEAD
fi

echo "Done."

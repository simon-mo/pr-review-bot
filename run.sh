#!/usr/bin/env bash
# Usage: ./run.sh [--fetch]
#
# Full pipeline: fetch (if needed), train, evaluate, push. By default skips
# fetch when you already have enough PRs. Use --fetch to force re-download.

set -euo pipefail

DO_FETCH=
while [[ "${1:-}" == --* ]]; do
    if [[ "$1" == "--fetch" ]]; then DO_FETCH=1; fi
    shift
done

# Need at least batch_size*3 for training (batch 15 => 45)
NEED_PR_COUNT=45
count_prs() { find data/prs -maxdepth 2 -name meta.json 2>/dev/null | wc -l | tr -d ' '; }
PR_COUNT=$(count_prs)

echo "═══════════════════════════════════════════════════"
echo "  PR Review Bot — Full Pipeline"
echo "═══════════════════════════════════════════════════"
echo ""

if [[ -n "$DO_FETCH" ]] || [[ "${PR_COUNT:-0}" -lt "$NEED_PR_COUNT" ]]; then
    echo "[$(date '+%H:%M:%S')] Step 1/3: Fetching PRs (random sample, streaming below)..."
    echo "[$(date '+%H:%M:%S')]   \$ ./fetch.sh --batch 200 closed"
    ./fetch.sh --batch 200 closed
else
    echo "[$(date '+%H:%M:%S')] Step 1/3: Using existing PR data ($PR_COUNT PRs). Skipping fetch. (Use --fetch to re-download.)"
fi
echo ""
echo "[$(date '+%H:%M:%S')] Step 2/3: Training (streaming below)..."
echo "[$(date '+%H:%M:%S')]   \$ ./train.sh 10 15"
./train.sh 10 15
echo ""
echo "[$(date '+%H:%M:%S')] Step 3/3: Holdout evaluation (streaming below)..."
echo "[$(date '+%H:%M:%S')]   \$ ./evaluate.sh 20"
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
    echo "[$(date '+%H:%M:%S')]   \$ git push origin HEAD"
    echo "Pushing commits to origin..."
    git push origin HEAD
fi

echo "Done."

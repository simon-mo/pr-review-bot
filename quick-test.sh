#!/usr/bin/env bash
# Usage: ./quick-test.sh [--fetch]
#
# Sanity-check the full loop locally: fetch a small set of PRs (unless you
# already have enough), run one training round, evaluate on 2 holdout PRs.
# By default skips fetch if you already have enough PRs. Use --fetch to force
# re-download. To reset: git checkout main or git reset --hard origin/main.

set -euo pipefail

DO_FETCH=
while [[ "${1:-}" == --* ]]; do
    if [[ "$1" == "--fetch" ]]; then DO_FETCH=1; fi
    shift
done

# Need at least batch_size*3 PRs for training (batch 2 => 6)
NEED_PR_COUNT=6
count_prs() { find data/prs -maxdepth 2 -name meta.json 2>/dev/null | wc -l | tr -d ' '; }
PR_COUNT=$(count_prs)

echo "═══════════════════════════════════════════════════"
echo "  PR Review Bot — Quick Test (1 round, batch 2)"
echo "═══════════════════════════════════════════════════"
echo ""

# TTY=1: stream output, skip permission check, exit claude session when done.
export AGENT_TTY=1

if [[ -n "$DO_FETCH" ]] || [[ "${PR_COUNT:-0}" -lt "$NEED_PR_COUNT" ]]; then
    echo "[$(date '+%H:%M:%S')] Fetching 10 PRs (random sample)..."
    echo "[$(date '+%H:%M:%S')]   \$ ./fetch.sh --batch 10 closed"
    ./fetch.sh --batch 10 closed
else
    echo "[$(date '+%H:%M:%S')] Using existing PR data ($PR_COUNT PRs). Skipping fetch. (Use --fetch to re-download.)"
fi
echo ""
echo "[$(date '+%H:%M:%S')] Training 1 round, batch 2..."
echo "[$(date '+%H:%M:%S')]   \$ ./train.sh 1 2"
./train.sh 1 2
echo ""
echo "[$(date '+%H:%M:%S')] Holdout evaluation (2 PRs)..."
echo "[$(date '+%H:%M:%S')]   \$ ./evaluate.sh 2"
./evaluate.sh 2

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Quick Test Summary"
echo "═══════════════════════════════════════════════════"
echo "Round 1 metrics:"
cat results/metrics/round_1.json 2>/dev/null || echo "  (none)"
echo ""
echo "Holdout metrics:"
cat results/metrics/holdout.json 2>/dev/null || echo "  (none)"
echo ""
echo "Skills:"
ls skills/*.md 2>/dev/null || echo "  (none yet)"
echo ""
echo "Loop OK. Scale up with ./run.sh or more rounds/batch with ./train.sh."

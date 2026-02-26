#!/usr/bin/env bash
# Usage: ./quick-test.sh
#
# Sanity-check the full loop locally: fetch a small set of PRs, run one training
# round with a tiny batch, optionally evaluate on 2 holdout PRs, print summary.
# Use this to verify the pipeline works before scaling up (e.g. ./run.sh).
# To reset and re-run: use git (e.g. git checkout main, or git reset --hard origin/main).

set -euo pipefail

echo "═══════════════════════════════════════════════════"
echo "  PR Review Bot — Quick Test (1 round, batch 2)"
echo "═══════════════════════════════════════════════════"

./fetch.sh --batch 10 closed
./train.sh 1 2
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

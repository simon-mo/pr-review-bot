#!/usr/bin/env bash
# Usage: ./review.sh <pr_number>
#
# Reviews a live PR using trained skills. Fetches PR data if needed, outputs triage, commits review.

set -euo pipefail

PR=${1:?Usage: ./review.sh <pr_number>}
AGENT_CMD="${AGENT_CMD:-claude}"

echo "═══════════════════════════════════════════════════"
echo "  Reviewing PR #${PR}"
echo "═══════════════════════════════════════════════════"

./fetch.sh "$PR"

sed "s|{{PR_DIR}}|data/prs/${PR}|g; s|{{PR_NUMBER}}|${PR}|g" prompts/review_live_pr.md | $AGENT_CMD -p

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Full review: results/reviews/${PR}.md"
echo "═══════════════════════════════════════════════════"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -f "results/reviews/${PR}.md" ]]; then
    git add "results/reviews/${PR}.md"
    git diff --cached --quiet || git commit -m "review: PR #${PR}"
fi

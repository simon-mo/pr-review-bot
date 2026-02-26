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

REVIEW_PROMPT=$(sed "s|{{PR_DIR}}|data/prs/${PR}|g; s|{{PR_NUMBER}}|${PR}|g" prompts/review_live_pr.md)
if [[ "$AGENT_CMD" == "agent" ]]; then
    tmp=$(mktemp)
    printf '%s' "$REVIEW_PROMPT" > "$tmp"
    $AGENT_CMD -p "$(cat "$tmp")" --trust
    rm -f "$tmp"
else
    echo "$REVIEW_PROMPT" | $AGENT_CMD -p
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Full review: results/reviews/${PR}.md"
echo "═══════════════════════════════════════════════════"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -f "results/reviews/${PR}.md" ]]; then
    git add "results/reviews/${PR}.md"
    git diff --cached --quiet || git commit -m "review: PR #${PR}"
fi

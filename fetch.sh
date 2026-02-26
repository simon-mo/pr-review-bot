#!/usr/bin/env bash
# Usage: ./fetch.sh <pr_number> [pr_number...]
# Or:    ./fetch.sh --batch <count> <state>
#
# Fetches PR data from vllm-project/vllm into data/prs/<number>/

set -euo pipefail

REPO="vllm-project/vllm"
DATA_DIR="data/prs"

fetch_pr() {
    local pr=$1
    local dir="${DATA_DIR}/${pr}"

    if [[ -d "$dir" && -f "$dir/meta.json" ]]; then
        echo "  [skip] PR #${pr} already fetched"
        return 0
    fi

    mkdir -p "$dir"
    echo "  [fetch] PR #${pr}..."

    # Metadata
    gh pr view "$pr" --repo "$REPO" \
        --json number,title,state,body,author,labels,mergedAt,closedAt,createdAt,reviewDecision,additions,deletions,changedFiles,mergeCommit,headRefName,baseRefName \
        > "$dir/meta.json" 2>/dev/null || { echo "  [error] Failed to fetch PR #${pr}"; rm -rf "$dir"; return 1; }

    # Description (extracted from meta for convenience)
    python3 -c "
import json, sys
with open('$dir/meta.json') as f:
    d = json.load(f)
print(d.get('body') or '(no description)')
" > "$dir/description.md"

    # Diff
    gh pr diff "$pr" --repo "$REPO" > "$dir/diff.patch" 2>/dev/null || echo "" > "$dir/diff.patch"

    # Changed files list
    gh pr view "$pr" --repo "$REPO" --json files \
        | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('files',[]),indent=2))" \
        > "$dir/files.json"

    # Reviews (approve/request changes/comment)
    gh api "repos/${REPO}/pulls/${pr}/reviews" --paginate \
        2>/dev/null > "$dir/reviews.json" || echo "[]" > "$dir/reviews.json"

    # Inline review comments
    gh api "repos/${REPO}/pulls/${pr}/comments" --paginate \
        2>/dev/null > "$dir/review_comments.json" || echo "[]" > "$dir/review_comments.json"

    # Conversation comments
    gh api "repos/${REPO}/issues/${pr}/comments" --paginate \
        2>/dev/null > "$dir/comments.json" || echo "[]" > "$dir/comments.json"

    # Timeline (events)
    gh api "repos/${REPO}/issues/${pr}/timeline" --paginate \
        2>/dev/null > "$dir/timeline.json" || echo "[]" > "$dir/timeline.json"

    echo "  [done] PR #${pr}"
}

fetch_batch() {
    local count=${1:-50}
    local state=${2:-closed}

    echo "Fetching list of ${count} ${state} PRs..."

    # Get PR numbers
    gh pr list --repo "$REPO" --state "$state" --limit "$count" \
        --json number -q '.[].number' | while read -r pr; do
        fetch_pr "$pr"
        sleep 0.5  # Rate limit courtesy
    done
}

# Main
if [[ "${1:-}" == "--batch" ]]; then
    shift
    fetch_batch "${1:-50}" "${2:-closed}"
else
    for pr in "$@"; do
        fetch_pr "$pr"
        sleep 0.3
    done
fi

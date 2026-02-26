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
    local progress=${2:-}
    local dir="${DATA_DIR}/${pr}"

    if [[ -d "$dir" && -f "$dir/meta.json" ]]; then
        echo "  ${progress}[skip] PR #${pr} already fetched"
        return 0
    fi

    mkdir -p "$dir"
    echo "  ${progress}[fetch] PR #${pr}..."

    # Metadata
    gh pr view "$pr" --repo "$REPO" \
        --json number,title,state,body,author,labels,mergedAt,closedAt,createdAt,reviewDecision,additions,deletions,changedFiles,mergeCommit,headRefName,baseRefName \
        > "$dir/meta.json" 2>/dev/null || { echo "  ${progress}[error] Failed to fetch PR #${pr}"; rm -rf "$dir"; return 1; }

    # Description (extracted from meta for convenience)
    python -u -c "
import json, sys
with open('$dir/meta.json') as f:
    d = json.load(f)
print(d.get('body') or '(no description)')
" > "$dir/description.md"

    # Diff
    gh pr diff "$pr" --repo "$REPO" > "$dir/diff.patch" 2>/dev/null || echo "" > "$dir/diff.patch"

    # Changed files list
    gh pr view "$pr" --repo "$REPO" --json files \
        | python -u -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('files',[]),indent=2))" \
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

    echo "  ${progress}[done] PR #${pr}" 1>&2
}

fetch_batch() {
    local count=${1:-50}
    local state=${2:-closed}

    echo "[$(date '+%H:%M:%S')] Sampling ${count} PRs (merged + closed + well-reviewed mix)..." 1>&2
    # Random stratified sample — do not use chronological/PR-number order
    local list
    list=$(python -u utils.py sample-prs-to-fetch --count "$count" --repo "$REPO") || exit 1
    local total
    total=$(echo "$list" | grep -c . || echo 0)
    echo "[$(date '+%H:%M:%S')] Fetching ${total} PRs (streaming progress below)..." 1>&2

    local i=0
    while read -r pr; do
        [[ -z "${pr:-}" ]] && continue
        i=$((i + 1))
        fetch_pr "$pr" "[${i}/${total}] "
        sleep 0.5  # Rate limit courtesy
    done <<< "$list"
    echo "[$(date '+%H:%M:%S')] Batch fetch complete." 1>&2
}

# Main
if [[ "${1:-}" == "--batch" ]]; then
    shift
    fetch_batch "${1:-50}" "${2:-closed}"
else
    for pr in "$@"; do
        fetch_pr "$pr" ""
        sleep 0.3
    done
fi

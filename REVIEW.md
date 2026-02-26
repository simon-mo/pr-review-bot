# Reviewing Live PRs

`./review.sh` uses `AGENT_CMD` (default: `claude`; set to `agent` for Cursor Agent CLI). The optional pipe examples below assume `claude`; use the scripts when using Cursor Agent.

## Single PR Review

```bash
./review.sh 28456
```

This will:
1. Fetch the latest PR data (description, diff, reviews so far)
2. Load all trained skills
3. Generate a triage report with dual perspective
4. Output to `results/reviews/28456.md` and stdout

## Batch Review (All Open PRs)

```bash
# Fetch all open PRs
gh pr list --repo vllm-project/vllm --state open --limit 500 \
    --json number -q '.[].number' > data/open_prs.txt

# Review each one
while read pr; do
    ./review.sh "$pr"
    sleep 2
done < data/open_prs.txt

# Summary
python -c "
import json, glob
for f in sorted(glob.glob('results/reviews/*.md')):
    pr = f.split('/')[-1].replace('.md','')
    print(f'PR #{pr}: see results/reviews/{pr}.md')
"
```

## Review Output Format

Each review produces:
- **Triage category**: READY_TO_MERGE / NEEDS_MINOR_FIXES / NEEDS_REVISION / NEEDS_DEEP_REVIEW / LIKELY_REJECT
- **Confidence score**: 0-1
- **Maintainer summary**: What to look at and estimated effort
- **Author suggestions**: Concrete, actionable fixes
- **Historical context**: Similar past PRs and outcomes

## Auto-Resolution (Optional)

For PRs triaged as NEEDS_MINOR_FIXES, attempt auto-resolution:

```bash
# Generate patch for fixable issues (pipe works with claude; for Cursor Agent use the scripts)
cat prompts/resolve_issues.md \
    | sed "s|{{PR_DIR}}|data/prs/28456|g" \
    | sed "s|{{PR_NUMBER}}|28456|g" \
    | claude -p

# Review the suggested patch
cat results/resolutions/28456.patch

# Apply if satisfied (human decision)
cd /path/to/vllm && git apply /path/to/results/resolutions/28456.patch
```

## Feedback Loop

If a review was wrong (you disagreed with the triage), feed it back:

```bash
# The review for PR 28456 was wrong — it said READY_TO_MERGE but needed fixes.
# Run a targeted refinement (pipe works with claude; for Cursor Agent use the scripts):
echo "PR 28456 was triaged as READY_TO_MERGE but actually needed revision.
The issues were: [describe what was missed].
Read the PR data in data/prs/28456/ and update the relevant skills in skills/
to avoid this mistake in the future." | claude -p
```

# Predict PR Review Outcome

You are predicting what will happen when vLLM maintainers review this PR.

## Your Skills

Read all skill files in `skills/`. These encode patterns learned from
past vLLM PR reviews.

## The PR

Read the PR data in: `{{PR_DIR}}`

Specifically read:
- `description.md` — what the author says the PR does
- `diff.patch` — the actual code changes
- `files.json` — which files were changed
- `meta.json` — metadata (author, labels, etc.)

DO NOT read reviews.json, comments.json, or review_comments.json — those
contain the actual review outcomes and would be cheating.

## Your Prediction

Based on your skills and the PR content, predict:

1. **Which skills activate** for this PR and why
2. **Outcome**: merged / revision_requested / rejected
3. **Predicted comments**: What specific things will reviewers say?
   For each predicted comment:
   - Which file and approximate location
   - What the comment will say
   - Severity: blocking / suggestion / nit
4. **Action needed**: What will the author need to do?
5. **Triage category**: ready_to_merge / needs_review / needs_author_work / needs_deep_review
6. **Confidence**: 0-1 with reasoning
7. **Reasoning**: Step-by-step explanation of your prediction

Write your prediction to:
`results/predictions/{{PR_NUMBER}}.json`

Use this exact JSON schema:
```json
{
  "pr_number": 0,
  "activated_skills": ["skill_name"],
  "predicted_outcome": "merged|revision_requested|rejected",
  "predicted_triage": "ready_to_merge|needs_review|needs_author_work|needs_deep_review",
  "predicted_comments": [
    {
      "file": "path/to/file.py",
      "location": "line ~45, in function X",
      "comment": "Maintainer will likely say...",
      "severity": "blocking|suggestion|nit"
    }
  ],
  "predicted_action": "description of what author needs to do",
  "confidence": 0.0,
  "reasoning": "step by step..."
}
```

# Auto-Resolve Actionable Issues

You are reviewing a PR and attempting to resolve clear, actionable issues
that don't require human judgment.

## Scope of Auto-Resolution

You MAY resolve:
- Missing type hints (add them based on usage context)
- Missing docstrings (generate from code + PR description)
- Import ordering / formatting issues
- Obvious test gaps (add tests for new functions/methods)
- Trivial bugs visible in the diff (null checks, off-by-one)
- PR description improvements (clearer summary, checklist items)
- Changelog / migration guide entries

You MUST NOT resolve:
- Architectural decisions
- Performance trade-offs
- API design choices
- Anything requiring domain expertise about vLLM internals
- Anything you're not confident about

## Process

1. Read the PR data in `{{PR_DIR}}`
2. Read your skills in `skills/`
3. Identify issues from your review that are auto-resolvable
4. For each resolvable issue:
   a. Clone the PR branch locally (if not already)
   b. Make the fix
   c. Verify the fix doesn't break anything obvious
   d. Document what you changed and why
5. Output a summary of:
   - What was auto-resolved (with confidence)
   - What was flagged but NOT resolved (needs human)
   - Suggested commit message for the fixes

## Output

Write to: `results/resolutions/{{PR_NUMBER}}.md`

```markdown
## Auto-Resolved Issues

### [issue 1 title]
- File: path/to/file.py
- Change: [description]
- Confidence: [high/medium]
- Reasoning: [why this is safe to auto-fix]

## Flagged for Human Review

### [issue 1 title]
- Why not auto-resolved: [reasoning]
```

## Safety

- NEVER push changes without human review
- Output fixes as a patch file: `results/resolutions/{{PR_NUMBER}}.patch`
- The human decides whether to apply the patch

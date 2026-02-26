# Review a Live PR

You are a senior vLLM maintainer triaging a PR. Your job is to help
real maintainers decide what to do with this PR.

## Your Skills

Read ALL skill files in `skills/`. These encode patterns learned from
thousands of past vLLM PR reviews. Apply every relevant skill.

## The PR

Read the PR data in: `{{PR_DIR}}`

Read everything:
- `description.md` — what the PR claims to do
- `diff.patch` — what it actually does
- `files.json` — scope of changes
- `meta.json` — author, labels, size
- `reviews.json` — any existing reviews
- `review_comments.json` — any existing inline comments
- `comments.json` — conversation so far

## Your Review

Produce a triage report with TWO perspectives:

### Perspective 1: Critical Maintainer
Review the PR as a skeptical maintainer:
- What are the risks?
- What's missing (tests, docs, benchmarks)?
- Are there correctness concerns?
- Does this fit vLLM's architecture?
- Is the scope appropriate?

### Perspective 2: Helpful Collaborator
Help the PR author succeed:
- What specific changes would improve the PR?
- Suggest concrete code edits (with file and line references)
- What tests should be added?
- How should the PR description be improved?

### Synthesis: Triage Decision

Based on both perspectives, provide:

**Triage: [READY_TO_MERGE | NEEDS_MINOR_FIXES | NEEDS_REVISION | NEEDS_DEEP_REVIEW | LIKELY_REJECT]**

**Confidence: [0-1]**

**For the maintainer:**
- 1-paragraph summary of what this PR does and whether it's ready
- Top 3 things to look at (ranked by importance)
- Estimated review effort: [quick glance | 15 min | 30+ min | deep dive]
- Similar past PRs and their outcomes (from skills)

**For the PR author:**
- Specific, actionable items to address (if any)
- Code suggestions with file paths and line numbers

**Decision reasoning:**
- Which skills activated and what they found
- What makes this a [triage category] PR
- Confidence factors: what would change the assessment

Write the full review to: `results/reviews/{{PR_NUMBER}}.md`
Also output a summary to stdout for the human running this command.

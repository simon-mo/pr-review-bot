# vLLM PR Review Bot — Bootstrap & Design Document

## Philosophy

This repo is **mostly markdown, not code.** The intelligence lives in skills (markdown files) and prompts that are fed to a CLI agent (Claude Code or Cursor). The agent does the thinking. We do the orchestrating.

**Principles:**
1. **No custom agent loop.** Shell out to `claude` CLI or `cursor` CLI. They handle the LLM calls, tool use, file I/O, and iteration.
2. **Skills are emergent, not pre-defined.** The training loop starts with zero skills. The agent observes PR review patterns and creates skills as it discovers them. Skills evolve, split, merge, and die based on measured accuracy.
3. **PR data is just directories.** Each PR gets a folder with its metadata, diff, comments, and reviews as plain files. The agent reads the filesystem.
4. **The repo itself evolves.** The agent can modify its own scripts, prompts, and structure. Version control tracks what changed and why.
5. **Minimal code.** A fetcher script, an orchestrator shell script, and metrics. Everything else is generated on the fly or handled via prompts.

---

## Repo Structure

```
vllm-pr-bot/
├── README.md                       # This file
├── TRAINING.md                     # Training loop documentation
├── REVIEW.md                       # Live PR review documentation
├── METRICS.md                      # Metrics definitions and anti-gaming
│
├── skills/                         # Learned skills (emergent, not seeded)
│   └── .gitkeep                    # Starts empty — agent creates these
│
├── prompts/
│   ├── discover_skills.md          # Prompt: observe PRs → create/refine skills
│   ├── predict_review.md           # Prompt: predict PR outcome using skills
│   ├── evaluate_prediction.md      # Prompt: compare prediction to reality
│   ├── refine_skills.md            # Prompt: update skills based on evaluation
│   ├── review_live_pr.md           # Prompt: review a live PR for triage
│   └── resolve_issues.md          # Prompt: auto-resolve actionable issues
│
├── data/
│   ├── prs/                        # One directory per PR (created by fetcher)
│   │   └── .gitkeep
│   ├── training_sets/              # Lists of PR numbers for each batch
│   └── holdout/                    # PR numbers reserved for evaluation
│
├── results/
│   ├── predictions/                # Prediction JSONs per PR
│   ├── evaluations/                # Evaluation JSONs per PR
│   ├── metrics/                    # Accuracy logs per training round
│   └── skill_changelog.md          # Auto-maintained log of skill evolution
│
├── fetch.sh                        # Fetch PR data into data/prs/NNNNN/
├── train.sh                        # Run one training iteration
├── review.sh                       # Review a single live PR
├── evaluate.sh                     # Run metrics on holdout set
└── utils.py                        # Minimal helper (diff stats, sampling)
```

**That's it.** ~5 files of actual code. Everything else is markdown and data.

---

## Data Layout

Each PR is a directory. The agent reads these files directly.

```
data/prs/18234/
├── meta.json          # { number, title, author, labels, state, merged, created_at, closed_at, ... }
├── description.md     # PR body / description
├── diff.patch         # Full unified diff
├── files.json         # [ { filename, status, additions, deletions } ]
├── reviews.json       # [ { author, state, body, submitted_at } ]
├── review_comments.json  # [ { author, body, path, line, created_at } ]  (inline comments)
├── comments.json      # [ { author, body, created_at } ]  (conversation thread)
└── timeline.json      # Key events in order
```

Created by `fetch.sh`. Nothing fancy — just `gh` CLI calls dumped to files.

---

## fetch.sh

```bash
#!/usr/bin/env bash
# Usage: ./fetch.sh <pr_number> [pr_number...]
# Or:    ./fetch.sh --batch <count> --state closed --sort created --direction desc
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
    fetch_batch "${2:-50}" "${3:-closed}"
else
    for pr in "$@"; do
        fetch_pr "$pr"
        sleep 0.3
    done
fi
```

---

## The Skills System

### What is a Skill?

A skill is a **markdown file** in `skills/`. It encodes a review pattern the agent has learned. Skills are created, refined, split, merged, and deleted by the agent during training.

There are NO pre-defined skills. The `skills/` directory starts empty.

### Skill Format

Skills are markdown because the agent reads and writes markdown natively. No YAML parsing, no schema enforcement — just text the agent can reason about.

```markdown
# Skill: [name]

## When This Applies
[Conditions under which this skill should be activated — file patterns,
diff characteristics, PR metadata patterns]

## What I've Learned
[Patterns observed from training PRs, written in plain language.
Each pattern includes evidence PR numbers.]

## Review Checklist
[Specific things to check when this skill is active.
Grounded in observed maintainer behavior, not generic advice.]

## Common Mistakes
[Patterns that look like issues but maintainers actually don't care about.
False positives from training — things to NOT flag.]

## Prediction Heuristics
[Decision rules for predicting outcome when this skill is relevant.
e.g., "If touching scheduler + no benchmark → 80% chance of revision request"]

## Accuracy
- Training samples: [N]
- Correct predictions: [N]
- Accuracy: [%]
- Last updated: [date]
- Trend: [improving/stable/declining]
```

### Skill Evolution Rules

The agent follows these rules (encoded in the training prompts):

1. **Creation:** When the agent sees a review pattern that no existing skill covers, it creates a new skill file.
2. **Refinement:** After each training batch, skills are updated with new patterns and accuracy data.
3. **Splitting:** If a skill's accuracy is low and the agent identifies distinct sub-patterns, it splits into multiple skills.
4. **Merging:** If two skills consistently activate together and cover overlapping patterns, merge them.
5. **Deprecation:** If a skill's accuracy stays below 40% after 3 refinement rounds, archive it to `skills/_archived/`.
6. **No hoarding:** Maximum 20 active skills. Forces prioritization.

---

## Prompts

### prompts/discover_skills.md

```markdown
# Discover Skills from PR Review Data

You are analyzing closed PRs from the vLLM project to discover review
patterns and create skills.

## Your Task

Read the PR data in the directories listed below. For each PR, study:
1. The description and diff (what changed)
2. The review comments (what reviewers said)
3. The final outcome (merged or rejected, and why)

Look for PATTERNS — recurring things reviewers care about. Not generic
code review advice, but specific vLLM maintainer behaviors:
- What file paths trigger extra scrutiny?
- What kinds of changes get approved quickly vs slowly?
- What do reviewers consistently flag?
- What gets PRs rejected?
- Are there reviewer-specific patterns?

## Current Skills

Read all files in `skills/` to see what patterns are already captured.

## Instructions

1. Read each PR directory in the batch
2. For each PR, note what reviewers focused on and what the outcome was
3. After reading all PRs, identify patterns that are NOT yet captured
   by existing skills
4. For new patterns: create a new skill file in `skills/`
5. For patterns that extend existing skills: update the relevant skill
6. For each skill you create or modify, explain your reasoning

## Rules
- DO NOT create generic skills like "check for bugs" or "review code quality"
- Every pattern must cite specific PR numbers as evidence
- Skills must be actionable — a reviewer reading the skill should know
  exactly what to look for
- Maximum 20 active skills. If you need a new one and are at the limit,
  merge or deprecate first.
- Write skills as markdown files in `skills/` named with snake_case

## PR Directories to Analyze

{{PR_DIRS}}
```

### prompts/predict_review.md

```markdown
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
```

### prompts/evaluate_prediction.md

```markdown
# Evaluate Prediction Accuracy

You made a prediction for PR #{{PR_NUMBER}}. Now compare it to reality.

## Your Prediction

Read: `results/predictions/{{PR_NUMBER}}.json`

## What Actually Happened

NOW read the review data you were not allowed to see before:
- `{{PR_DIR}}/reviews.json` — reviewer verdicts
- `{{PR_DIR}}/review_comments.json` — inline code comments
- `{{PR_DIR}}/comments.json` — conversation thread
- `{{PR_DIR}}/meta.json` — final state (merged or not)

## Evaluate

For each aspect of your prediction:

1. **Outcome match**: Did you predict merged/rejected/revision correctly?
2. **Comment match**: For each predicted comment, was there a real comment
   about the same thing? Score each as: hit / partial / miss
3. **Missed issues**: What did real reviewers flag that you didn't predict?
4. **False alarms**: What did you predict that reviewers didn't care about?
5. **Triage match**: Was your triage category appropriate?
6. **Skill assessment**: For each skill that activated:
   - Did it help make a correct prediction?
   - Did it lead to a false positive?
   - Did it miss something it should have caught?

## Output

Write evaluation to: `results/evaluations/{{PR_NUMBER}}.json`

```json
{
  "pr_number": 0,
  "outcome_match": "correct|partial|wrong",
  "triage_match": "correct|partial|wrong",
  "comment_hits": 0,
  "comment_misses": 0,
  "false_alarms": 0,
  "missed_issues": ["description of each missed issue"],
  "false_alarm_details": ["description of each false alarm"],
  "skill_performance": {
    "skill_name": {
      "helped": true,
      "false_positives": 0,
      "missed": 0,
      "notes": "..."
    }
  },
  "overall_accuracy": 0.0,
  "key_insight": "The most important thing learned from this evaluation"
}
```

## Hypothesis

After writing the evaluation, think about WHY you were wrong (if you were).
Write a brief hypothesis at the end — this will feed into skill refinement.
Append it to the JSON as "hypothesis": "..."
```

### prompts/refine_skills.md

```markdown
# Refine Skills Based on Training Batch

You just completed a training batch. Now refine the skills.

## Evaluation Data

Read all evaluation files in `results/evaluations/` from this batch:
{{EVAL_FILES}}

## Current Skills

Read all files in `skills/`.

## Your Task

1. **Aggregate results**: What's the overall accuracy? Which skills
   performed well? Which performed poorly?

2. **Update each skill** that was activated in this batch:
   - Add new patterns discovered from the evaluations
   - Remove or demote patterns that led to false alarms
   - Update accuracy numbers
   - Add evidence PR numbers

3. **Create new skills** if evaluations reveal patterns not covered
   by existing skills. Follow the skill format in skills/.

4. **Consider structural changes**:
   - Split skills that are too broad (low accuracy, diverse miss patterns)
   - Merge skills that always activate together
   - Archive skills consistently below 40% accuracy

5. **Update the changelog**: Append to `results/skill_changelog.md`
   what you changed and why.

## Rules
- Every change must cite specific PR evaluations as evidence
- Don't over-fit to a single PR — a pattern needs at least 2 PRs
- Keep skills concise — a reviewer should be able to read a skill in 2 minutes
- Preserve high-performing patterns even when refactoring
- Update accuracy numbers honestly
```

### prompts/review_live_pr.md

```markdown
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
```

### prompts/resolve_issues.md

```markdown
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
```

---

## train.sh — The Training Orchestrator

```bash
#!/usr/bin/env bash
# Usage: ./train.sh [--rounds N] [--batch-size N] [--sample-strategy stratified|random]
#
# Runs the training loop:
#   1. Fetch a batch of closed PRs (if not already fetched)
#   2. Agent observes PRs and discovers/refines skills
#   3. Agent predicts outcomes for unseen PRs
#   4. Agent evaluates predictions against reality
#   5. Agent refines skills based on evaluation
#   Repeat.

set -euo pipefail

ROUNDS=${1:-5}
BATCH_SIZE=${2:-10}
AGENT_CMD="${AGENT_CMD:-claude}"  # "claude" for Claude Code, or "cursor" for Cursor CLI
REPO="vllm-project/vllm"

# ── Helpers ──────────────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

sample_prs() {
    local count=$1
    local strategy=${2:-stratified}
    python3 utils.py sample --count "$count" --strategy "$strategy"
}

pick_training_batch() {
    # Pick PRs from data/prs/ that haven't been used in training yet
    python3 utils.py pick-batch --size "$BATCH_SIZE"
}

pick_prediction_batch() {
    # Pick PRs to predict on (separate from discovery batch)
    python3 utils.py pick-batch --size "$BATCH_SIZE" --exclude-used
}

run_agent() {
    local prompt_file=$1
    shift
    local vars=("$@")

    # Build the prompt with variable substitution
    local prompt
    prompt=$(cat "$prompt_file")
    for var in "${vars[@]}"; do
        local key="${var%%=*}"
        local val="${var#*=}"
        prompt="${prompt//\{\{$key\}\}/$val}"
    done

    # Run the agent
    echo "$prompt" | $AGENT_CMD --print --no-input
}

# ── Ensure we have data ─────────────────────────────────────────────

ensure_data() {
    local fetched
    fetched=$(find data/prs -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    if (( fetched < BATCH_SIZE * 3 )); then
        log "Need more PR data. Fetching..."
        ./fetch.sh --batch $((BATCH_SIZE * 5)) closed
    fi
}

# ── Training Round ──────────────────────────────────────────────────

run_round() {
    local round=$1
    log "════════ ROUND $round ════════"

    # Step 1: Discover skills from a batch of PRs
    log "Step 1: Skill discovery..."
    local discover_batch
    discover_batch=$(pick_training_batch)
    local pr_dirs
    pr_dirs=$(echo "$discover_batch" | xargs -I{} echo "data/prs/{}" | tr '\n' ' ')

    run_agent prompts/discover_skills.md "PR_DIRS=$pr_dirs"

    # Step 2: Predict outcomes for a DIFFERENT batch
    log "Step 2: Predicting outcomes..."
    local predict_batch
    predict_batch=$(pick_prediction_batch)

    for pr in $predict_batch; do
        log "  Predicting PR #${pr}..."
        run_agent prompts/predict_review.md \
            "PR_DIR=data/prs/${pr}" \
            "PR_NUMBER=${pr}"
    done

    # Step 3: Evaluate predictions
    log "Step 3: Evaluating predictions..."
    for pr in $predict_batch; do
        log "  Evaluating PR #${pr}..."
        run_agent prompts/evaluate_prediction.md \
            "PR_DIR=data/prs/${pr}" \
            "PR_NUMBER=${pr}"
    done

    # Step 4: Refine skills
    log "Step 4: Refining skills..."
    local eval_files
    eval_files=$(echo "$predict_batch" | xargs -I{} echo "results/evaluations/{}.json" | tr '\n' ' ')

    run_agent prompts/refine_skills.md "EVAL_FILES=$eval_files"

    # Step 5: Compute metrics
    log "Step 5: Computing metrics..."
    python3 utils.py compute-metrics --round "$round"

    log "Round $round complete. Metrics:"
    cat "results/metrics/round_${round}.json"
}

# ── Main ────────────────────────────────────────────────────────────

log "Starting training: $ROUNDS rounds, batch size $BATCH_SIZE"
ensure_data
mkdir -p results/{predictions,evaluations,metrics,reviews,resolutions}

for (( r=1; r<=ROUNDS; r++ )); do
    run_round "$r"
    log ""
done

log "Training complete. Run ./evaluate.sh for holdout metrics."
log "Skills are in skills/. Review results/skill_changelog.md for evolution history."
```

---

## review.sh — Review a Live PR

```bash
#!/usr/bin/env bash
# Usage: ./review.sh <pr_number>
#
# Reviews a live PR using trained skills.
# Fetches latest PR data, applies all skills, outputs triage report.

set -euo pipefail

PR=$1
AGENT_CMD="${AGENT_CMD:-claude}"

echo "═══════════════════════════════════════════════════"
echo "  Reviewing PR #${PR}"
echo "═══════════════════════════════════════════════════"

# Fetch latest PR data
./fetch.sh "$PR"

# Run the review agent
cat prompts/review_live_pr.md \
    | sed "s|{{PR_DIR}}|data/prs/${PR}|g" \
    | sed "s|{{PR_NUMBER}}|${PR}|g" \
    | $AGENT_CMD --print --no-input

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Full review: results/reviews/${PR}.md"
echo "═══════════════════════════════════════════════════"
```

---

## evaluate.sh — Holdout Evaluation

```bash
#!/usr/bin/env bash
# Usage: ./evaluate.sh [--holdout-size N]
#
# Evaluates skill accuracy on held-out PRs that were never used in training.

set -euo pipefail

SIZE=${1:-20}
AGENT_CMD="${AGENT_CMD:-claude}"

echo "Running holdout evaluation on $SIZE PRs..."

# Get holdout PRs (never used in training)
HOLDOUT=$(python3 utils.py get-holdout --size "$SIZE")

CORRECT=0
TOTAL=0

for pr in $HOLDOUT; do
    echo "  Evaluating PR #${pr}..."

    # Predict (agent cannot see reviews)
    cat prompts/predict_review.md \
        | sed "s|{{PR_DIR}}|data/prs/${pr}|g" \
        | sed "s|{{PR_NUMBER}}|${pr}|g" \
        | $AGENT_CMD --print --no-input

    # Evaluate
    cat prompts/evaluate_prediction.md \
        | sed "s|{{PR_DIR}}|data/prs/${pr}|g" \
        | sed "s|{{PR_NUMBER}}|${pr}|g" \
        | $AGENT_CMD --print --no-input

    TOTAL=$((TOTAL + 1))
done

# Compute aggregate metrics
python3 utils.py compute-holdout-metrics

echo ""
echo "Holdout evaluation complete. Results: results/metrics/holdout.json"
```

---

## utils.py — Minimal Utility Script

```python
#!/usr/bin/env python3
"""Minimal utilities for the PR review bot. Handles sampling, metrics,
and batch management. Everything else is done by the agent."""

import json
import os
import random
import sys
from datetime import datetime
from pathlib import Path

DATA_DIR = Path("data/prs")
RESULTS_DIR = Path("results")
TRAINING_LOG = Path("data/training_sets/used_prs.txt")


def get_all_pr_numbers():
    """List all fetched PR numbers."""
    return sorted([
        int(d.name) for d in DATA_DIR.iterdir()
        if d.is_dir() and d.name.isdigit() and (d / "meta.json").exists()
    ])


def get_used_prs():
    """Get PRs already used in training."""
    if not TRAINING_LOG.exists():
        return set()
    return set(int(x.strip()) for x in TRAINING_LOG.read_text().splitlines() if x.strip())


def mark_used(pr_numbers):
    """Mark PRs as used in training."""
    TRAINING_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(TRAINING_LOG, "a") as f:
        for pr in pr_numbers:
            f.write(f"{pr}\n")


def load_pr_meta(pr_number):
    """Load PR metadata."""
    meta_path = DATA_DIR / str(pr_number) / "meta.json"
    if meta_path.exists():
        with open(meta_path) as f:
            return json.load(f)
    return None


def classify_pr(meta):
    """Classify a PR into a stratum for stratified sampling."""
    if not meta:
        return "unknown"

    merged = meta.get("mergedAt") is not None
    state = meta.get("state", "")
    additions = meta.get("additions", 0)
    deletions = meta.get("deletions", 0)

    if not merged and state == "CLOSED":
        return "rejected"
    if additions + deletions <= 10:
        return "trivial"
    if additions + deletions > 500:
        return "large"
    return "standard"


def sample_stratified(count):
    """Stratified sampling across PR types."""
    all_prs = get_all_pr_numbers()
    used = get_used_prs()
    available = [p for p in all_prs if p not in used]

    # Classify into strata
    strata = {}
    for pr in available:
        meta = load_pr_meta(pr)
        stratum = classify_pr(meta)
        strata.setdefault(stratum, []).append(pr)

    # Sample proportionally, ensuring each stratum is represented
    sampled = []
    per_stratum = max(1, count // max(len(strata), 1))
    for stratum, prs in strata.items():
        n = min(per_stratum, len(prs))
        sampled.extend(random.sample(prs, n))

    # Fill remaining slots randomly
    remaining = [p for p in available if p not in sampled]
    needed = count - len(sampled)
    if needed > 0 and remaining:
        sampled.extend(random.sample(remaining, min(needed, len(remaining))))

    return sampled[:count]


def pick_batch(size, exclude_used=False):
    """Pick a batch of PRs for training or prediction."""
    all_prs = get_all_pr_numbers()
    used = get_used_prs()

    if exclude_used:
        available = [p for p in all_prs if p not in used]
    else:
        available = all_prs

    if len(available) < size:
        print(f"Warning: only {len(available)} PRs available, requested {size}", file=sys.stderr)
        size = len(available)

    batch = random.sample(available, size)
    mark_used(batch)
    return batch


def compute_metrics(round_num=None):
    """Compute accuracy metrics from evaluation results."""
    eval_dir = RESULTS_DIR / "evaluations"
    if not eval_dir.exists():
        return {}

    evals = []
    for f in eval_dir.glob("*.json"):
        try:
            with open(f) as fh:
                evals.append(json.load(fh))
        except (json.JSONDecodeError, KeyError):
            continue

    if not evals:
        return {"error": "no evaluations found"}

    # Aggregate metrics
    outcome_correct = sum(1 for e in evals if e.get("outcome_match") == "correct")
    triage_correct = sum(1 for e in evals if e.get("triage_match") == "correct")
    total = len(evals)

    total_hits = sum(e.get("comment_hits", 0) for e in evals)
    total_misses = sum(e.get("comment_misses", 0) for e in evals)
    total_false_alarms = sum(e.get("false_alarms", 0) for e in evals)

    # Precision and recall for comments
    comment_precision = total_hits / max(total_hits + total_false_alarms, 1)
    comment_recall = total_hits / max(total_hits + total_misses, 1)

    # Per-skill accuracy
    skill_stats = {}
    for e in evals:
        for skill, perf in e.get("skill_performance", {}).items():
            if skill not in skill_stats:
                skill_stats[skill] = {"helped": 0, "total": 0, "false_positives": 0, "missed": 0}
            skill_stats[skill]["total"] += 1
            if perf.get("helped"):
                skill_stats[skill]["helped"] += 1
            skill_stats[skill]["false_positives"] += perf.get("false_positives", 0)
            skill_stats[skill]["missed"] += perf.get("missed", 0)

    metrics = {
        "timestamp": datetime.now().isoformat(),
        "round": round_num,
        "total_evaluated": total,
        "outcome_accuracy": outcome_correct / max(total, 1),
        "triage_accuracy": triage_correct / max(total, 1),
        "comment_precision": comment_precision,
        "comment_recall": comment_recall,
        "comment_f1": 2 * comment_precision * comment_recall / max(comment_precision + comment_recall, 0.001),
        "skill_performance": {
            k: {**v, "accuracy": v["helped"] / max(v["total"], 1)}
            for k, v in skill_stats.items()
        },
        "total_skills": len(list(Path("skills").glob("*.md"))),
    }

    # Save
    metrics_dir = RESULTS_DIR / "metrics"
    metrics_dir.mkdir(parents=True, exist_ok=True)
    out_path = metrics_dir / (f"round_{round_num}.json" if round_num else "latest.json")
    with open(out_path, "w") as f:
        json.dump(metrics, f, indent=2)

    return metrics


# ── CLI ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"

    if cmd == "sample":
        count = int(sys.argv[sys.argv.index("--count") + 1]) if "--count" in sys.argv else 50
        prs = sample_stratified(count)
        print("\n".join(str(p) for p in prs))

    elif cmd == "pick-batch":
        size = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 10
        exclude = "--exclude-used" in sys.argv
        batch = pick_batch(size, exclude_used=exclude)
        print("\n".join(str(p) for p in batch))

    elif cmd == "get-holdout":
        size = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 20
        all_prs = get_all_pr_numbers()
        used = get_used_prs()
        holdout = [p for p in all_prs if p not in used]
        print("\n".join(str(p) for p in holdout[:size]))

    elif cmd == "compute-metrics":
        round_num = int(sys.argv[sys.argv.index("--round") + 1]) if "--round" in sys.argv else None
        m = compute_metrics(round_num)
        print(json.dumps(m, indent=2))

    elif cmd == "compute-holdout-metrics":
        m = compute_metrics(round_num=None)
        out = RESULTS_DIR / "metrics" / "holdout.json"
        with open(out, "w") as f:
            json.dump(m, f, indent=2)
        print(json.dumps(m, indent=2))

    else:
        print("Usage: python utils.py <command>")
        print("Commands: sample, pick-batch, get-holdout, compute-metrics, compute-holdout-metrics")
```

---

## TRAINING.md — Training Loop Documentation

```markdown
# Training Process

## Overview

The training loop teaches the agent to review vLLM PRs by having it:
1. Observe real PR reviews to discover patterns (→ creates skills)
2. Predict outcomes of unseen PRs using those skills
3. Compare predictions to reality
4. Refine skills based on what it got wrong

Skills start from ZERO. The agent creates them as it discovers patterns.

## Prerequisites

- `gh` CLI authenticated with access to vllm-project/vllm
- Claude Code (`claude`) or Cursor CLI (`cursor`) installed
- Set `AGENT_CMD` env var if not using Claude Code (default: `claude`)

## Quick Start

```bash
# 1. Fetch initial PR data (50 closed PRs)
./fetch.sh --batch 50 closed

# 2. Run 5 training rounds
./train.sh 5 10

# 3. Check results
cat results/metrics/round_5.json
ls skills/  # See what skills were discovered

# 4. Run holdout evaluation
./evaluate.sh 20
```

## Training Round Details

Each round does 4 things:

### Step 1: Skill Discovery
The agent reads a batch of PRs WITH their review outcomes and looks for
patterns. It creates new skill files or updates existing ones.

### Step 2: Prediction
The agent reads a DIFFERENT batch of PRs WITHOUT review outcomes and
predicts what will happen using its skills.

### Step 3: Evaluation
The agent reveals the actual outcomes and scores its predictions.
It identifies hits, misses, and false alarms.

### Step 4: Refinement
The agent reads all evaluations from the batch and refines skills.
It may create, update, split, merge, or archive skills.

## Scaling Up

```bash
# Fetch more data (500 PRs covering different strata)
./fetch.sh --batch 500 closed

# Run overnight (20 rounds, larger batches)
./train.sh 20 25

# Monitor progress
watch -n 60 'ls results/metrics/ | tail -5 | xargs -I{} cat results/metrics/{}'
```

## Interpreting Results

After training, check:
- `skills/` — The discovered skills (the main deliverable)
- `results/metrics/` — Accuracy over time (should trend upward)
- `results/skill_changelog.md` — What changed and why
- `results/evaluations/` — Individual PR evaluations for debugging
```

---

## REVIEW.md — Live PR Review Documentation

```markdown
# Reviewing Live PRs

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
python3 -c "
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
# Generate patch for fixable issues
cat prompts/resolve_issues.md \
    | sed "s|{{PR_DIR}}|data/prs/28456|g" \
    | sed "s|{{PR_NUMBER}}|28456|g" \
    | claude --print --no-input

# Review the suggested patch
cat results/resolutions/28456.patch

# Apply if satisfied (human decision)
cd /path/to/vllm && git apply /path/to/results/resolutions/28456.patch
```

## Feedback Loop

If a review was wrong (you disagreed with the triage), feed it back:

```bash
# The review for PR 28456 was wrong — it said READY_TO_MERGE but needed fixes.
# Run a targeted refinement:
echo "PR 28456 was triaged as READY_TO_MERGE but actually needed revision.
The issues were: [describe what was missed].
Read the PR data in data/prs/28456/ and update the relevant skills in skills/
to avoid this mistake in the future." | claude --print --no-input
```
```

---

## METRICS.md — Metrics & Anti-Gaming

```markdown
# Metrics System

## Core Metrics

### 1. Outcome Accuracy
- **What**: Did we predict merged/rejected/revision_requested correctly?
- **Target**: >70%
- **Anti-gaming**: Measured ONLY on holdout PRs never seen during training.
  The holdout set is selected BEFORE training begins and locked.

### 2. Triage Accuracy
- **What**: Was the triage category (ready/needs review/needs work/deep review) correct?
- **Target**: >65%
- **Anti-gaming**: Same holdout set. Also measured by human agreement
  (when we start using it on real PRs).

### 3. Comment Precision
- **What**: Of the comments we predicted, how many matched real reviewer comments?
- **Formula**: true_positives / (true_positives + false_positives)
- **Target**: >50%
- **Anti-gaming**: Being conservative (fewer predictions) is fine — we
  measure recall separately.

### 4. Comment Recall
- **What**: Of the real reviewer comments, how many did we predict?
- **Formula**: true_positives / (true_positives + false_negatives)
- **Target**: >40%
- **Anti-gaming**: Being aggressive (many predictions) hurts precision.
  F1 balances this.

### 5. Comment F1
- **What**: Harmonic mean of precision and recall
- **Target**: >0.45
- **Why F1**: Prevents gaming by being either too conservative or too aggressive

### 6. Per-Skill Accuracy
- **What**: For each skill, what fraction of activations led to correct predictions?
- **Target**: >50% per skill (below 40% = archive candidate)
- **Anti-gaming**: Skills that activate on everything get diluted accuracy.
  Skills must have meaningful trigger conditions.

## Anti-Reward-Hacking Measures

### Problem: Trivial Prediction Strategy
A bot that always predicts "merged" would be ~85% accurate on outcome
(since ~85% of closed PRs are merged).

**Countermeasure**: Stratified evaluation. The holdout set has equal
representation of merged, rejected, and revision-requested PRs. Accuracy
is measured per-stratum and averaged, so trivial strategies score ~33%.

### Problem: Vague Predictions
A bot that predicts "this PR might need some changes" for every PR is
technically often right but useless.

**Countermeasure**: Comment predictions must be SPECIFIC — file, location,
and concrete issue. Vague predictions don't count as hits. The evaluation
prompt explicitly checks for specificity.

### Problem: Over-Fitting to Training Data
A bot that memorizes specific PRs instead of learning patterns.

**Countermeasure**:
1. Holdout set is never used in training
2. Skills must cite at least 2 evidence PRs per pattern
3. Periodically shuffle and re-sample the holdout set
4. Track accuracy on RECENT PRs (last 6 months) separately from
   older PRs to detect temporal over-fitting

### Problem: Skill Proliferation
Creating many narrow skills that each match one PR perfectly.

**Countermeasure**: Maximum 20 active skills. If a skill has fewer than
5 training samples, it can't be used in production. Skills under 40%
accuracy after 3 rounds are archived.

### Problem: Confidence Calibration
A bot that always says "confidence: 0.95" or always says "confidence: 0.5".

**Countermeasure**: Measure calibration — of predictions with confidence
0.8-0.9, are ~85% correct? Plot calibration curve. Poorly calibrated
confidence scores are flagged in metrics.

### Problem: Agent Modifying Its Own Metrics
Since the agent can write to results/, it could fake metrics.

**Countermeasure**: The metrics computation in utils.py is deterministic
Python code, not agent-generated. The agent writes predictions and
evaluations, but utils.py computes the aggregate metrics independently.
Git history tracks all changes.

## Running Metrics

```bash
# After training
python3 utils.py compute-metrics --round 5

# Holdout evaluation (independent of training)
./evaluate.sh 20

# Quick dashboard
python3 -c "
import json, glob
rounds = sorted(glob.glob('results/metrics/round_*.json'))
for r in rounds:
    with open(r) as f:
        m = json.load(f)
    print(f'Round {m[\"round\"]}: outcome={m[\"outcome_accuracy\"]:.0%} '
          f'triage={m[\"triage_accuracy\"]:.0%} '
          f'F1={m[\"comment_f1\"]:.2f} '
          f'skills={m[\"total_skills\"]}')
"
```

## Nightly Training Target

When running overnight, the optimization target is:

**Maximize**: Weighted composite score
```
score = 0.30 * outcome_accuracy_stratified
      + 0.25 * triage_accuracy
      + 0.25 * comment_f1
      + 0.10 * calibration_score
      + 0.10 * (1 - skill_count / 20)  # Reward parsimony
```

The last term rewards having FEWER skills that work well over MANY
skills that are mediocre. This fights skill proliferation.

**Guard rails**: Training stops if:
- Any metric drops >20% from previous round (sign of catastrophic refinement)
- Total skills exceeds 20 (force consolidation before continuing)
- Same PR appears in both training and holdout (data leak)

These checks are in utils.py and enforced by train.sh.
```

---

## Summary: What's Actually In This Repo

| Path | Type | Purpose |
|------|------|---------|
| `skills/` | Markdown files | The deliverable — learned review patterns |
| `prompts/` | Markdown files | Instructions for the agent at each step |
| `fetch.sh` | Shell script | Pulls PR data from GitHub |
| `train.sh` | Shell script | Orchestrates the training loop |
| `review.sh` | Shell script | Reviews a single live PR |
| `evaluate.sh` | Shell script | Runs holdout evaluation |
| `utils.py` | Python script | Sampling, metrics, batch management |
| `TRAINING.md` | Docs | How to run training |
| `REVIEW.md` | Docs | How to review PRs |
| `METRICS.md` | Docs | Metrics definitions + anti-gaming |
| `data/prs/` | PR data dirs | Fetched PR data (not committed) |
| `results/` | JSON + Markdown | Predictions, evaluations, metrics |

**Total code**: ~200 lines of Python, ~100 lines of Bash.
**Everything else is prompts and documentation.**
The agent does the thinking.
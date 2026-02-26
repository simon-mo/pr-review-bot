# vLLM PR Review Bot

An AI-powered triage system for vLLM pull requests. It learns from the project's ~20,000 closed PRs to predict how maintainers will review new PRs, what comments they'll leave, and whether the PR is ready to merge.

The intelligence lives in **skills** — markdown files that encode learned review patterns — and **prompts** that instruct Claude Code to discover, refine, and apply those skills. The repo contains almost no application code. Everything runs locally. The `gh` CLI fetches PR data; Claude Code does the thinking; `git` versions everything the agent produces.

## How It Works

**Training:** The agent reads batches of closed vLLM PRs — their diffs, review comments, approval status — and discovers patterns in how maintainers review code. It encodes these patterns as skill files. Then it predicts outcomes for PRs it hasn't seen, compares to reality, hypothesizes why it was wrong, and refines the skills. After each training round, the agent commits its changes to a branch so you can see exactly what evolved and roll back if needed.

**Review:** Point the agent at a live PR number. It loads all trained skills, reads the PR data, and produces a triage report: should this be merged, does it need specific fixes, or does it need deep human review? It plays both sides — critical maintainer and helpful collaborator — so the output is useful to both reviewers and PR authors.

**Skills are emergent.** The `skills/` directory starts empty. The agent creates skills as it discovers patterns. Skills evolve, split, merge, and get archived based on measured accuracy. There is no pre-defined taxonomy.

## Quick Start

```bash
# Prerequisites
gh auth status       # GitHub CLI, authenticated
claude --version     # Claude Code CLI

# One command to run everything
./run.sh
```

`run.sh` does the full pipeline: fetches PR data, runs training rounds, evaluates accuracy, commits results. Run it once overnight and come back to trained skills in the morning.

For finer control:

```bash
./fetch.sh --batch 50 closed     # Fetch 50 closed PRs
./train.sh 5 10                   # 5 training rounds, 10 PRs per batch
./evaluate.sh 20                  # Evaluate on 20 held-out PRs
./review.sh 28456                 # Review a specific live PR
```

## How Git Is Used

Git is the versioning and storage layer. The agent commits incrementally as it works:

```
main                          # Your starting point
 └── training/round-1         # Branch per training round
      ├── skills discovered   # Agent commits new skill files
      ├── predictions made    # Agent commits prediction JSONs
      ├── evaluations done    # Agent commits evaluation JSONs
      └── skills refined      # Agent commits updated skills
 └── training/round-2         # Next round branches from previous
      └── ...
```

This gives you:
- **Full history** of how every skill evolved (`git log skills/`)
- **Easy rollback** if a training round made things worse (`git checkout training/round-3`)
- **Diffable skills** — `git diff training/round-1..training/round-5 -- skills/` shows exactly what the agent learned
- **Branching for experiments** — try different batch sizes or prompt tweaks on separate branches

The agent merges each successful round back to `main` and pushes, so the remote always has the latest good state.

## Repo Structure

```
├── design.md              # Full architecture and design rationale
├── TRAINING.md            # Training loop documentation
├── REVIEW.md              # Live PR review documentation
├── METRICS.md             # Metrics definitions and anti-gaming measures
│
├── skills/                # Learned skills (starts empty, agent populates)
│
├── prompts/               # Agent instructions for each phase
│   ├── discover_skills.md
│   ├── predict_review.md
│   ├── evaluate_prediction.md
│   ├── refine_skills.md
│   ├── review_live_pr.md
│   └── resolve_issues.md
│
├── data/prs/              # One directory per PR (fetched by fetch.sh)
├── results/               # Predictions, evaluations, metrics, reviews
│
├── run.sh                 # Full pipeline: fetch → train → evaluate
├── fetch.sh               # Fetch PR data via gh CLI
├── train.sh               # Run training loop via Claude Code
├── review.sh              # Review a single live PR
├── evaluate.sh            # Run holdout evaluation
└── utils.py               # Sampling, metrics, batch management
```

## Key Design Decisions

**No CI, no cloud, no infrastructure.** This runs on your laptop. `gh` downloads data, `claude` thinks, `git` saves. That's the entire stack.

**Git as the iteration layer.** Instead of a database or artifact store, the agent uses git branches and commits to track its own progress. Each training round is a branch. You can diff, revert, cherry-pick, and branch just like any codebase. This also means you can push to a remote and pick up training on another machine.

**Skills as markdown, not config.** The agent reads and writes markdown natively. Skills are human-readable, diffable, and editable by hand. No schema, no parser.

**Emergent skills, not pre-defined.** The `skills/` directory starts empty. The agent discovers what matters from actual review data rather than encoding our assumptions about what matters.


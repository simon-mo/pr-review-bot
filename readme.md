# vLLM PR Review Bot

An AI-powered triage system for vLLM pull requests. It learns from the project's closed PRs to predict how maintainers will review new PRs, what comments they'll leave, and whether the PR is ready to merge.

The intelligence lives in **skills** — markdown files that encode learned review patterns — and **prompts** that instruct the agent to discover, refine, and apply those skills. The repo contains minimal code: `fetch.sh`, `train.sh`, `review.sh`, `evaluate.sh`, `run.sh`, `quick-test.sh`, and `utils.py`. Everything runs locally. The `gh` CLI fetches PR data; Claude Code (`claude`) or Cursor Agent CLI (`agent`) does the thinking (set `AGENT_CMD=agent` to use Cursor; default is `claude`); `git` versions everything the agent produces.

**Current status:** Bootstrap (Phase 1) is complete — all prompts, scripts, and docs are in place (Booster commit). **Next:** run the pipeline to fetch data and train (Phase 2). See Quick Start below.

## How It Works

**Training:** The agent reads batches of closed vLLM PRs — their diffs, review comments, approval status — and discovers patterns in how maintainers review code. It encodes these patterns as skill files. Then it predicts outcomes for PRs it hasn't seen, compares to reality, hypothesizes why it was wrong, and refines the skills. After each training round, the agent commits its changes to a branch so you can see exactly what evolved and roll back if needed.

**Review:** Point the agent at a live PR number. It loads all trained skills, reads the PR data, and produces a triage report: should this be merged, does it need specific fixes, or does it need deep human review? It plays both sides — critical maintainer and helpful collaborator — so the output is useful to both reviewers and PR authors.

**Skills are emergent.** The `skills/` directory starts empty. The agent creates skills as it discovers patterns. Skills evolve, split, merge, and get archived based on measured accuracy. There is no pre-defined taxonomy.

## Quick Start (Phase 2: Fetch & Train)

**Prerequisites:** GitHub CLI authenticated (`gh auth status`). Claude Code (`claude --version`) or Cursor Agent CLI (`agent --version`) on PATH; set `AGENT_CMD=agent` to use Cursor (default: `claude`).

**Quick test (sanity-check the loop locally):**

```bash
AGENT_CMD=agent ./quick-test.sh   # or omit AGENT_CMD to use claude
```

This fetches 10 PRs, runs 1 training round (batch size 2), evaluates on 2 holdout PRs, and prints a summary. To reset and re-run, use git (e.g. `git checkout main` or `git reset --hard origin/main`).

**Full pipeline (recommended for first run):**

```bash
./run.sh
```

This fetches 200 closed PRs from vllm-project/vllm, runs 10 training rounds (batch size 15), evaluates on 20 holdout PRs, prints a summary, and pushes commits to `origin` if the remote exists. Allow time for fetch and multiple agent invocations (e.g. run overnight).

**Stepwise (finer control):**

```bash
./fetch.sh --batch 200 closed    # Fetch 200 closed PRs into data/prs/
./train.sh 10 15                 # 10 rounds, 15 PRs per discovery/prediction batch
./evaluate.sh 20                 # Evaluate on 20 held-out PRs
./review.sh <pr_number>          # Review a specific live PR (after training)
```

See `TRAINING.md` for round details and `design.md` for implementation status and next phase.

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
├── design.md              # Architecture, status, and next phase
├── TRAINING.md            # Training loop documentation
├── REVIEW.md              # Live PR review documentation
├── METRICS.md             # Metrics and anti-gaming
├── prompts/               # Agent instructions (discover, predict, evaluate, refine, review, resolve)
├── skills/                # Learned skills (starts empty; agent populates)
├── data/prs/              # One directory per PR (fetched by fetch.sh; gitignored)
├── results/               # Predictions, evaluations, metrics, reviews (tracked)
├── run.sh                 # Full pipeline: fetch → train → evaluate → push
├── quick-test.sh          # Quick test: 1 round, batch 2 (sanity-check loop locally)
├── fetch.sh               # Fetch PR data via gh CLI
├── train.sh               # Training loop (uses AGENT_CMD: claude or agent)
├── review.sh              # Review a single live PR
├── evaluate.sh            # Holdout evaluation
└── utils.py               # Sampling, metrics, batch management
```

## Key Design Decisions

**No CI, no cloud, no infrastructure.** This runs on your laptop. `gh` downloads data, the agent (Claude Code or Cursor Agent CLI per `AGENT_CMD`) thinks, `git` saves. That's the entire stack.

**Git as the iteration layer.** Instead of a database or artifact store, the agent uses git branches and commits to track its own progress. Each training round is a branch. You can diff, revert, cherry-pick, and branch just like any codebase. This also means you can push to a remote and pick up training on another machine.

**Skills as markdown, not config.** The agent reads and writes markdown natively. Skills are human-readable, diffable, and editable by hand. No schema, no parser.

**Emergent skills, not pre-defined.** The `skills/` directory starts empty. The agent discovers what matters from actual review data rather than encoding our assumptions about what matters.


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
- Claude Code (`claude`) or Cursor Agent CLI (`agent`) installed
- Set `AGENT_CMD=agent` to use Cursor (default: `claude`)

## Quick test

To sanity-check the full loop locally before scaling up:

```bash
./quick-test.sh   # Uses AGENT_CMD (default claude); or AGENT_CMD=agent ./quick-test.sh
```

This fetches 10 PRs, runs 1 round with batch size 2, and evaluates on 2 holdout PRs. To reset and re-run, use git (e.g. `git checkout main` or `git reset --hard origin/main`).

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

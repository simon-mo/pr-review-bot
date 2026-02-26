# Phase 2: Fetch data and run training

You are in the pr-review-bot repo. Phase 1 (Bootstrap) is complete — all scripts, prompts, and docs exist. Your job is to run **Phase 2: Fetch & Train**.

## What to do

1. **Prerequisites**
   - Confirm `gh` is authenticated and can access vllm-project/vllm: run `gh auth status` and, if needed, `gh pr list --repo vllm-project/vllm --limit 1`.
   - Confirm Claude Code is available: run `claude --version` or `which claude`.

2. **Run the full pipeline**
   - From the repo root run: `./run.sh`
   - This will: fetch 200 closed PRs, run 10 training rounds (batch size 15), evaluate on 20 holdout PRs, print a summary, and push to origin if the remote exists.
   - Do not modify scripts or prompts unless a command fails and you need to fix a bug.

3. **If you prefer stepwise execution**
   - `./fetch.sh --batch 200 closed` — wait for completion (idempotent; safe to re-run).
   - `./train.sh 10 15` — 10 rounds, 15 PRs per discovery and prediction batch; each round invokes Claude via `claude -p` with the appropriate prompt.
   - `./evaluate.sh 20` — holdout evaluation and metrics.
   - If a remote exists: `git push origin HEAD`.

4. **Handle failures**
   - **gh auth / rate limit:** If `fetch.sh` fails on auth or rate limit, report the error and suggest `gh auth login` or reducing batch size / adding delay.
   - **claude not found:** If `claude` is not on PATH, report and suggest installing Claude Code or setting `AGENT_CMD` to the correct CLI.
   - **Script errors:** If a script exits non-zero, run it in a way that shows the full error (e.g. no `|| true`), then fix the underlying cause (script bug, missing file, or env) and re-run only the failed step.
   - **Missing data:** If training or evaluate fails because there are not enough PRs, run `./fetch.sh --batch <larger_count> closed` first, then re-run training or evaluate.

5. **Report outcome**
   - After a successful run: list the contents of `skills/` (if any), show the last few lines or path of `results/metrics/holdout.json`, and note whether push to origin was done.
   - If the run was partial or failed: say what completed, what failed, and what you changed or recommend (e.g. run again, fix auth, or adjust batch sizes).

Do not fetch PR data in a way that bypasses `fetch.sh` (e.g. do not write new fetchers). Do not run training or evaluation without using the existing scripts. Execute from the repository root.

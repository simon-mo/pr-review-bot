#!/usr/bin/env python
"""Minimal utilities for the PR review bot. Handles sampling, metrics,
and batch management. Everything else is done by the agent."""

import json
import os
import random
import subprocess
import sys
from datetime import datetime
from pathlib import Path

DATA_DIR = Path("data/prs")
RESULTS_DIR = Path("results")
TRAINING_LOG = Path("data/training_sets/used_prs.txt")


def get_all_pr_numbers():
    """List all fetched PR numbers."""
    if not DATA_DIR.exists():
        return []
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
    additions = meta.get("additions", 0) or 0
    deletions = meta.get("deletions", 0) or 0

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

    strata = {}
    for pr in available:
        meta = load_pr_meta(pr)
        stratum = classify_pr(meta)
        strata.setdefault(stratum, []).append(pr)

    sampled = []
    per_stratum = max(1, count // max(len(strata), 1))
    for stratum, prs in strata.items():
        n = min(per_stratum, len(prs))
        sampled.extend(random.sample(prs, n))

    remaining = [p for p in available if p not in sampled]
    needed = count - len(sampled)
    if needed > 0 and remaining:
        sampled.extend(random.sample(remaining, min(needed, len(remaining))))

    return sampled[:count]


def sample_prs_to_fetch(repo, count):
    """Sample PR numbers to fetch from multiple strata (merged, closed, well-reviewed, etc.)
    to avoid chronological/PR-number bias. Uses gh CLI."""
    limit_per_pool = max(count * 2, 200)
    pools = []

    def run_gh_pr_list(state, extra_args=None):
        args = ["gh", "pr", "list", "--repo", repo, "--state", state, "--limit", str(limit_per_pool), "--json", "number", "-q", ".[].number"]
        if extra_args:
            args = args[:8] + extra_args + args[8:]
        try:
            out = subprocess.run(args, capture_output=True, text=True, timeout=60)
            if out.returncode == 0 and out.stdout.strip():
                return [int(n) for n in out.stdout.strip().splitlines() if n.strip().isdigit()]
        except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
            pass
        return []

    def run_gh_search(query_suffix, limit=300):
        query = f"repo:{repo} is:pr {query_suffix}"
        try:
            out = subprocess.run(
                ["gh", "search", "prs", query, "--limit", str(limit), "--json", "number", "-q", ".[].number"],
                capture_output=True, text=True, timeout=90,
            )
            if out.returncode == 0 and out.stdout.strip():
                return [int(n) for n in out.stdout.strip().splitlines() if n.strip().isdigit()]
        except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
            pass
        return []

    # (a) Merged PRs
    pools.append(run_gh_pr_list("merged"))
    # (b) Closed but not merged
    pools.append(run_gh_search("is:closed -is:merged", limit=limit_per_pool))
    # (c) Well-reviewed: merged with review approval (search proxy)
    pools.append(run_gh_search("is:merged review:approved", limit=limit_per_pool))
    # (d) Merged again with different sort (quick-merge proxy: recently updated/created spread)
    pools.append(run_gh_pr_list("merged"))

    combined = []
    seen = set()
    for pool in pools:
        for pr in pool:
            if pr not in seen:
                seen.add(pr)
                combined.append(pr)
    random.shuffle(combined)
    return combined[:count]


def pick_batch(size, exclude_used=True):
    """Pick a batch of PRs for training or prediction. Always uses PRs not yet used."""
    all_prs = get_all_pr_numbers()
    used = get_used_prs()
    available = [p for p in all_prs if p not in used]

    if len(available) < size:
        print(f"Warning: only {len(available)} PRs available, requested {size}", file=sys.stderr)
        size = max(0, len(available))

    if size == 0:
        return []

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

    outcome_correct = sum(1 for e in evals if e.get("outcome_match") == "correct")
    triage_correct = sum(1 for e in evals if e.get("triage_match") == "correct")
    total = len(evals)

    total_hits = sum(e.get("comment_hits", 0) for e in evals)
    total_misses = sum(e.get("comment_misses", 0) for e in evals)
    total_false_alarms = sum(e.get("false_alarms", 0) for e in evals)

    comment_precision = total_hits / max(total_hits + total_false_alarms, 1)
    comment_recall = total_hits / max(total_hits + total_misses, 1)

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

    skills_dir = Path("skills")
    total_skills = len([f for f in skills_dir.glob("*.md") if f.is_file()]) if skills_dir.exists() else 0

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
        "total_skills": total_skills,
    }

    metrics_dir = RESULTS_DIR / "metrics"
    metrics_dir.mkdir(parents=True, exist_ok=True)
    out_path = metrics_dir / (f"round_{round_num}.json" if round_num else "latest.json")
    with open(out_path, "w") as f:
        json.dump(metrics, f, indent=2)

    return metrics


def main():
    if len(sys.argv) < 2 or sys.argv[1] == "help":
        print("Usage: python utils.py <command> [options]")
        print("Commands:")
        print("  help                  Show this message")
        print("  sample                Stratified sample of PRs (--count N, --strategy stratified|random)")
        print("  sample-prs-to-fetch   Random PR numbers to fetch (--count N, --repo OWNER/REPO)")
        print("  pick-batch            Pick a batch for training (--size N, optional --exclude-used)")
        print("  get-holdout           Get PR numbers for holdout evaluation (--size N)")
        print("  compute-metrics       Compute accuracy from evaluations (--round N)")
        print("  compute-holdout-metrics  Write holdout metrics to results/metrics/holdout.json")
        return 0

    cmd = sys.argv[1]

    if cmd == "sample":
        count = 50
        if "--count" in sys.argv:
            count = int(sys.argv[sys.argv.index("--count") + 1])
        prs = sample_stratified(count)
        print("\n".join(str(p) for p in prs))

    elif cmd == "sample-prs-to-fetch":
        count = 50
        repo = os.environ.get("REPO", "vllm-project/vllm")
        if "--count" in sys.argv:
            count = int(sys.argv[sys.argv.index("--count") + 1])
        if "--repo" in sys.argv:
            repo = sys.argv[sys.argv.index("--repo") + 1]
        prs = sample_prs_to_fetch(repo, count)
        print("\n".join(str(p) for p in prs))

    elif cmd == "pick-batch":
        size = 10
        if "--size" in sys.argv:
            size = int(sys.argv[sys.argv.index("--size") + 1])
        exclude = "--exclude-used" in sys.argv
        batch = pick_batch(size, exclude_used=True)
        print("\n".join(str(p) for p in batch))

    elif cmd == "get-holdout":
        size = 20
        if "--size" in sys.argv:
            size = int(sys.argv[sys.argv.index("--size") + 1])
        all_prs = get_all_pr_numbers()
        used = get_used_prs()
        holdout = [p for p in all_prs if p not in used]
        for p in holdout[:size]:
            print(p)

    elif cmd == "compute-metrics":
        round_num = None
        if "--round" in sys.argv:
            idx = sys.argv.index("--round") + 1
            if idx < len(sys.argv):
                round_num = int(sys.argv[idx])
        m = compute_metrics(round_num)
        print(json.dumps(m, indent=2))

    elif cmd == "compute-holdout-metrics":
        m = compute_metrics(round_num=None)
        out = RESULTS_DIR / "metrics" / "holdout.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        with open(out, "w") as f:
            json.dump(m, f, indent=2)
        print(json.dumps(m, indent=2))

    else:
        print("Unknown command:", cmd, file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())

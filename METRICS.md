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

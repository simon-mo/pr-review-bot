# Trivial Changes: Predict Silence, Not Manufactured Nits

## Pattern

For **trivially simple PRs** (dead code deletion, one-line fixes, mechanical
cleanups) where a knowledgeable maintainer is involved (as author or reviewer),
the correct prediction is **zero substantive review comments**. Do not
manufacture hedging nits just to have a predicted comment.

## When this applies

- Pure deletion of dead/unused code where a maintainer already confirmed it's
  unused
- One-line fixes that follow an established pattern (e.g., setting
  `quant_config=None` on gate layers)
- Self-merges by project leads on their own infrastructure branches
- Small, single-file optimizations with benchmarks from known contributors
  (especially when labeled 'ready')
- Mechanical pattern-following changes (e.g., registering new ops across files
  following an established template)
- Any PR where: (simple mechanical change) + (high author/reviewer authority)
  + (fast merge time) = minimal review friction

## What NOT to predict

- "Reviewers may verify X is truly unused" — experienced maintainers know
  their codebase; they don't ask for proof of the obvious
- "Reviewers may ask for clarification on motivation" — when the change is
  self-evidently correct, no one asks why
- "Reviewers may note [minor optimization concern]" — when benchmarks are
  provided, don't manufacture performance nits on well-understood operations
- Generic "careful reviewer" concerns that project onto a codebase where
  maintainers have high familiarity

## Calibration rule

When confidence is very high on a mechanical change, predict silence. A false
negative (missing a rare comment on a trivial PR) is less costly than a false
positive (predicting friction that never happens). The base rate for
substantive review comments on trivial mechanical PRs by maintainers is near
zero.

**Trust the signal fully.** When this skill activates with strong indicators
(single-file + small diff + known contributor + benchmarks/ready label),
predict zero comments — do not hedge with a low-severity "reviewer may note"
suggestion. Hedging is the primary source of false alarms from this skill.

## Evidence

- **PR #35189**: Predicted "reviewers may verify padding_idx is truly unused"
  on a dead code deletion. DarkLight1337 was already confident — no reviewer
  raised this. (false alarm)
- **PR #35036**: Predicted 1 clarification comment on WoosukKwon's self-merged
  infrastructure PR. Zero comments in reality. (false alarm)
- **PR #35127**: Skill activated and helped correctly identify this as a clean
  change from a known contributor. However, prediction still hedged with 1
  suggestion about index_select + to('cpu'). PR received immediate
  unconditional approval with zero inline comments. (1 false alarm from
  hedging)
- **PR #35123**: Skill activated and correctly predicted silent human approval.
  Mechanical pattern-following change (registering ops) from an established
  contributor merged with zero human comments. (perfect prediction)

## Accuracy

- Activated: 4 times (PR #35036, #35189 retroactive; PR #35127, #35123 live)
- Correct silencing: 3/4 (PR #35123 perfect; #35036, #35189 retroactive)
- Insufficient silencing: 1/4 (PR #35127 — hedged when it should have
  predicted zero)
- False alarms prevented: 2 retroactive, 1 live (PR #35123)
- False alarms from hedging: 1 (PR #35127)

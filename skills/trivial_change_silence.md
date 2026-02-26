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
- Any PR where: (simple mechanical change) + (high author/reviewer authority)
  + (fast merge time) = minimal review friction

## What NOT to predict

- "Reviewers may verify X is truly unused" — experienced maintainers know
  their codebase; they don't ask for proof of the obvious
- "Reviewers may ask for clarification on motivation" — when the change is
  self-evidently correct, no one asks why
- Generic "careful reviewer" concerns that project onto a codebase where
  maintainers have high familiarity

## Calibration rule

When confidence is very high on a mechanical change, predict silence. A false
negative (missing a rare comment on a trivial PR) is less costly than a false
positive (predicting friction that never happens). The base rate for
substantive review comments on trivial mechanical PRs by maintainers is near
zero.

## Evidence

- **PR #35189**: Predicted "reviewers may verify padding_idx is truly unused"
  on a dead code deletion. DarkLight1337 was already confident — no reviewer
  raised this. (false alarm)
- **PR #35036**: Predicted 1 clarification comment on WoosukKwon's self-merged
  infrastructure PR. Zero comments in reality. (false alarm)

## Accuracy

- Activated: 0 times (retroactive pattern — would have prevented 2 false alarms)
- Estimated impact: prevents ~1 false alarm per batch on trivial PRs

# Skill Changelog

## 2026-02-26 — Training Batch (PR #35036)

### Batch Summary
- **PRs evaluated**: 1 (PR #35036)
- **Overall accuracy**: 0.85
- **Outcome/triage**: Both correct
- **False alarms**: 1
- **Skills activated**: None

### Existing Skill Updates
No existing skills were activated in this batch — no changes made to:
- `rocm_fusion_pattern_breakage.md`
- `refactoring_mechanical_errors.md`
- `large_refactor_review_expectations.md`

### Candidate Pattern (needs 2+ PRs to promote to skill)

**"High-authority self-merge zero-review" pattern**
- **Evidence so far**: PR #35036 (WoosukKwon self-merged his own Model Runner V2 infrastructure PR in 17 minutes, zero comments)
- **Hypothesis**: When the project lead merges their own PR on a feature branch they own, with an empty description and fast merge time, the correct prediction is zero review comments. The `REVIEW_REQUIRED` status is a repo policy artifact, not a signal of friction.
- **What went wrong**: The bot predicted 1 minor clarification comment because it pattern-matched on "what reviewers usually ask about" rather than reading the social signal (author authority + fast merge = no engagement).
- **Action**: Watch for this pattern in future batches. If confirmed by 1+ more PRs, create a `high_authority_self_merge.md` skill.

## 2026-02-26 — Training Batch (PR #35189, PR #34890)

### Batch Summary
- **PRs evaluated**: 2 (PR #35189, PR #34890)
- **Overall accuracy**: 0.70 (0.85 + 0.55)
- **Outcome**: 2/2 correct (100%)
- **Triage**: 1 correct, 1 partial (75%)
- **Comment hits**: 1, **misses**: 1, **false alarms**: 2
- **Skills activated**: None (no existing skills triggered)

### New Skill Created

**`trivial_change_silence.md`** — Predict silence on trivial mechanical changes
- **Promoted from**: "High-authority self-merge zero-review" candidate pattern
- **Evidence**: PR #35036 (self-merge, zero comments, predicted 1) + PR #35189 (dead code deletion, maintainer confident, predicted cautious nit that never came)
- **Why**: Both PRs had false alarms from manufacturing hedging nits on changes where maintainers were confident and engaged minimally. The pattern now has 2+ PRs: when a change is trivially simple and a knowledgeable maintainer is involved, predict zero substantive comments.
- **Expected impact**: Prevents ~1 false alarm per batch on trivial PRs

### Existing Skill Updates
No existing skills were activated in this batch — no changes made to:
- `rocm_fusion_pattern_breakage.md`
- `refactoring_mechanical_errors.md`
- `large_refactor_review_expectations.md`
- `moe_gate_quantization_exclusion.md`
- `openai_api_pydantic_validation.md`

### Candidate Patterns (needs 2+ PRs to promote to skill)

**"Dtype completeness check" pattern**
- **Evidence so far**: PR #34890 (PR added bf16 groupwise quantization support; maintainer tlrmchlsmth asked "Do we need to handle fp16 as well here?" — this led to actual code changes in a follow-up commit)
- **Hypothesis**: When a PR adds dtype-specific handling for one variant (e.g., bf16), reviewers will ask about adjacent dtype variants (e.g., fp16). The PR description even mentioned fp16 channelwise in its "Purpose" section but the code only handled bf16 groupwise — this gap was a signal.
- **Trigger**: PR adds or modifies dtype-specific code paths, especially in quantization/kernel layers
- **Action**: Watch for this pattern in future batches. If confirmed by 1+ more PRs, create a `dtype_completeness_check.md` skill.

**"Domain experts trust benchmarks" pattern**
- **Evidence so far**: PR #34890 (predicted reviewers would question float32 upcast latency overhead; no reviewer raised this — kernel developers already know the performance characteristics of dtype conversions)
- **Hypothesis**: In performance-critical areas (kernels, quantization), domain expert reviewers trust benchmark results without questioning well-understood overhead characteristics. Don't predict latency/overhead concerns when benchmarks are provided and the overhead mechanism is well-known.
- **Action**: Watch for this pattern in future batches. If confirmed by 1+ more PRs, create a skill or fold into `trivial_change_silence.md`.

## 2026-02-26 — Training Batch (PR #35127, PR #35123)

### Batch Summary
- **PRs evaluated**: 2 (PR #35127, PR #35123)
- **Overall accuracy**: 0.85 average
- **Outcome**: 2/2 correct (100%)
- **Triage**: 2/2 correct (100%)
- **Comment hits**: 0, **misses**: 0, **false alarms**: 1
- **Skills activated**: `trivial_change_silence` (both PRs), `large_refactor_review_expectations` (PR #35127, misapplied)

### Skill Updates

**`trivial_change_silence.md`** — Strengthened with new evidence
- Added PR #35127 and PR #35123 as evidence (first live activations)
- Added "well-benchmarked single-file optimizations" and "mechanical
  pattern-following changes" to trigger list
- Added "don't manufacture performance nits when benchmarks provided" to
  anti-patterns
- Added explicit "trust the signal fully" calibration guidance — hedging is
  the primary source of false alarms from this skill
- Updated accuracy: 4 activations, 3/4 correct silencing, 1/4 insufficient
  (hedged on PR #35127)
- **Why**: PR #35127 showed the skill correctly identified a trivial change
  but the prediction still hedged with a manufactured suggestion. PR #35123
  showed the skill working perfectly for a mechanical change.

**`large_refactor_review_expectations.md`** — Added scope gate
- Added "Scope gate" section: do not activate for single-file changes under
  ~100 lines, small optimizations, or changes with benchmarks
- Added PR #35127 as negative evidence (misapplied to +51/-15 single-file
  optimization)
- **Why**: PR #35127 evaluation noted this skill was misapplied — a small
  single-file optimization is not a "large refactor." The scope gate prevents
  future misactivation on small changes.

### Candidate Pattern Updates

**"Domain experts trust benchmarks" pattern** — Additional evidence
- PR #35127 provides partial reinforcement: well-benchmarked single-file
  optimization from a known contributor sailed through with zero comments.
  The false alarm was a manufactured performance nit that no reviewer raised.
- Now has 2 PRs of evidence (PR #34890, PR #35127). However, both cases are
  already covered by `trivial_change_silence` — this pattern may not need
  its own skill. Keep watching; if a non-trivial PR with benchmarks also
  gets silence on performance concerns, promote to standalone skill.

### No New Skills Created
- The missed issue in PR #35123 (missing `<torch/all.h>` header) was caught
  by an automated bot, not a human reviewer. Since our prediction target is
  human reviewer behavior, this doesn't warrant a new skill yet. The
  `trivial_change_silence` skill correctly predicted zero human comments.
- A "header/import completeness" skill could be valuable for predicting bot
  flags, but needs more evidence (only 1 PR so far).

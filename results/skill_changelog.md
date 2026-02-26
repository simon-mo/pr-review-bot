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

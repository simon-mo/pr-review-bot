# ROCm Compilation Fusion Pattern Breakage

## Pattern
Changes to custom op call signatures or tensor usage in `vllm/model_executor/layers/fused_moe/` can **silently break** ROCm-specific `torch.compile` fusion passes without any test failure or error — only a performance regression.

## What to look for
- Any change that adds a new **consumer** of a tensor output (e.g., passing `original_hidden_states` to an additional op) in the MoE forward path
- Changes to `torch.ops.vllm.moe_forward` or `torch.ops.vllm.moe_forward_shared` call signatures
- Any modification to custom op arguments in `default_moe_runner.py` or similar MoE runner files

## Why it matters
ROCm fusion passes in `vllm/compilation/passes/fusion/rocm_aiter_fusion.py` use `torch._inductor.pattern_matcher` which matches nodes by exact `num_users` count. If a tensor that previously had 2 users now has 3 (because a new op consumes it), the pattern match silently fails and the fusion is skipped. There is no error — just degraded performance.

## What to flag
1. "This change adds a new user of [tensor] — verify this doesn't break ROCm fusion pattern matching in `rocm_aiter_fusion.py`. Pattern matchers are sensitive to exact `_users=N` counts."
2. Ask the author to verify with compile traces on ROCm (e.g., `TORCH_COMPILE_DEBUG=1`) or at minimum provide before/after benchmark results on ROCm hardware.

## Evidence
- **PR #34636**: PR #32344 introduced a silent regression by passing `original_hidden_states` into `moe_forward`, which added a third user to the RMSNorm output tensor and broke the `AddAiterRMSNormPadPattern` match. The fix was to only save unpadded sizes when `shared_experts` is present.

## Files to watch
- `vllm/model_executor/layers/fused_moe/runner/*.py`
- `vllm/compilation/passes/fusion/rocm_aiter_fusion.py`
- Any file registering or calling `torch.ops.vllm.moe_forward*`

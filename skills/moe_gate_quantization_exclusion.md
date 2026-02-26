# MoE Gate Layer Quantization Exclusion

## Pattern

When adding or modifying Mixture-of-Experts (MoE) model implementations, the
**gate/router layer** (`mlp.gate`) must always be initialized with
`quant_config=None`, regardless of what the checkpoint metadata says.

MoE gate layers route tokens to experts and are stored in full precision in
checkpoints. However, some checkpoints (notably NVFP4 variants) fail to mark
these layers as excluded from quantization. If the model code passes the
global `quant_config` to the gate layer, weight loading will crash because it
tries to load full-precision weights as quantized.

## What to look for

- Any new model file in `vllm/model_executor/models/` that implements MoE
  architecture (look for `num_experts`, `FusedMoE`, gate/router layers)
- The gate layer constructor: verify it passes `quant_config=None`, not the
  parent's `quant_config`
- When an existing MoE model adds support for a new quantization format,
  confirm the gate exclusion is preserved

## Reviewer behavior

- `robertgshaw2-redhat`: Checks for consistency with existing MoE models.
  Quick approval when the pattern matches established convention.
- These fixes get fast-tracked when they follow the existing pattern (PR #35156
  was approved in 7 minutes).

## Files to watch

- `vllm/model_executor/models/qwen3_next.py`
- `vllm/model_executor/models/qwen2_moe.py`
- Any file creating a `ReplicatedLinear` or similar layer with a `gate` prefix
  inside an MoE block

## Evidence

- PR #35156: `nvidia/Qwen3.5-397B-A17B-NVFP4` crashed during weight loading
  because `mlp.gate` was passed `quant_config` instead of `None`. One-line fix,
  merged same day.

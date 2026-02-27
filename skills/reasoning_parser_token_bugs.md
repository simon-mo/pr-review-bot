# Reasoning Parser Token Detection Bugs

## Pattern
Reasoning parser implementations (`vllm/reasoning/*_reasoning_parser.py`) are
prone to subtle bugs in token detection logic, especially in streaming paths.
These bugs often don't cause crashes — they silently drop or misroute content
(reasoning appears as regular content, or `<think>` tags go missing).

## What to look for

### 1. Loop variable vs sequence confusion in `is_reasoning_end`
When iterating over `input_ids` to find end tokens, a common bug is comparing
the full sequence instead of the loop variable:
```python
# BUG: compares Sequence[int] to int — always False
for input_id in reversed(input_ids):
    if input_id in (end_token_id, start_token_id):
        return input_ids == end_token_id  # wrong! should be input_id

# CORRECT:
for input_id in reversed(input_ids):
    if input_id in (end_token_id, start_token_id):
        return input_id == end_token_id
```

### 2. Wrong default return value when no token is found
When `is_reasoning_end` scans token IDs and finds neither start nor end tokens,
the default return value matters. Returning `True` by default causes `<think>`
tags to be dropped after tool calls:
```python
# BUG: defaults to True when no relevant token found
for input_id in reversed(input_ids):
    if input_id in (end_token_id, start_token_id):
        return input_id == end_token_id
return True  # wrong! should be False
```

### 3. Multi-token delta edge cases in streaming
When streaming deltas contain multiple tokens, the `<think>` tag may span a
delta boundary or appear within a larger text chunk. Parsers must strip
`<think>` from delta text, not just detect it as a standalone token:
```python
# BUG: only handles <think> as first token, not embedded in multi-token delta
if delta == "<think>":
    ...

# CORRECT: strip <think> if it appears anywhere in the delta
if "<think>" in delta:
    delta = delta.replace("<think>", "", 1)
```

### 4. Cross-model start token placement
Different models in the same family may place `<think>` differently — some
generate it as model output, others place it in the prompt template. Parsers
that require both `<think>` and `</think>` in model output will fail for
variants where `<think>` is in the prompt:
```python
# BUG: assumes model always generates <think>
if "<think>" not in text or "</think>" not in text:
    return None  # fails for Qwen3.5 where <think> is in prompt

# CORRECT: handle both styles
if "</think>" in text:
    # extract reasoning, stripping <think> if present
```

## What to flag
1. Any new or modified `is_reasoning_end` method — verify loop variable names
   and default return values
2. Any `extract_reasoning_streaming` method — test with multi-token deltas
3. New reasoning parser classes — verify they handle model variants where
   start tokens are in prompts vs generated output
4. Changes to `serving.py` streaming paths — verify `prompt_is_reasoning_end_arr`
   is checked BEFORE calling the parser

## Files to watch
- `vllm/reasoning/*_reasoning_parser.py`
- `vllm/entrypoints/openai/chat_completion/serving.py` (streaming paths)
- `tests/reasoning/test_*_reasoning_parser.py`

## Evidence
- **PR #34779**: Three bugs in Qwen3 reasoning parser — Qwen3.5 models failed
  because parser required `<think>` in output (it's in the prompt template);
  streaming paths in `serving.py` didn't check `prompt_is_reasoning_end_arr`
  before calling parser, causing `enable_thinking=False` to misroute content.
- **PR #35352**: MiniMax M2 parser had `input_ids == end_token_id` (sequence vs
  int comparison, always False) and defaulted to returning `True` when no token
  found, causing `<think>` to be dropped after tool calls. Both caught in review.

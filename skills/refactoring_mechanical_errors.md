# Refactoring Mechanical Errors (Dict Keys, Variable Names)

## Pattern
Large refactors that change function signatures across many files are prone to **mechanical copy-paste errors**: wrong dictionary keys, stale variable names, and unit mismatches. These bugs are easy to miss because they don't cause syntax errors and may only manifest in specific code paths.

## What to look for

### 1. Dict key typos after signature changes
When a refactor consolidates function parameters into a dataclass or changes how kwargs are passed, check every site where dict literals are constructed. A common error is using the **field name** as a dict key instead of the original key:
```python
# BEFORE refactor:
tokenization_kwargs = {
    **(tokenization_kwargs or {}),
    "add_special_tokens": False,  # correct key
}

# AFTER refactor (BUG):
inputs.tokenization_kwargs = {
    **inputs.tokenization_kwargs,
    "tokenization_kwargs": False,  # wrong! should be "add_special_tokens"
}
```

### 2. Variable shadowing / stale references
When refactoring introduces new intermediate variables, check that downstream code uses the **new** variable, not the old one:
```python
# Processed result stored in mm_uuids
mm_uuids = self._process_mm_uuids(mm_uuid_items, ...)

# BUG: passes original mm_uuid_items instead of processed mm_uuids
MMProcessorInputs(prompt, mm_data_items, mm_uuid_items, ...)  # wrong!
```

### 3. Naming unit inconsistencies
When renaming metrics/fields, verify the naming convention is applied consistently across ALL files (source, benchmarks, docstrings):
```python
# Inconsistent: mixing _secs and _ms suffixes
'get_mm_hashes_secs': 0.02,
'merge_mm_kwargs_ms': 0.01,  # should be _secs
```

## What to flag
1. For every file where a function signature changed: verify each call site passes the correct keys/values
2. When new intermediate variables are introduced: trace every usage of the old variable name in the same function
3. When renaming metrics: grep for both old and new naming patterns to catch stragglers

## Evidence
- **PR #35083**: A 38-file refactor by a maintainer (DarkLight1337) contained:
  - Dict key typo in both `clip.py` and `siglip.py` (`"tokenization_kwargs"` instead of `"add_special_tokens"`)
  - Variable shadowing in `renderers/base.py` (using `mm_uuid_items` instead of processed `mm_uuids`)
  - Unit suffix inconsistency in docstring (`_ms` mixed with `_secs`)
  - All three were caught by automated review and fixed before merge

## Files to watch
- Any PR touching 5+ files with signature changes in `vllm/model_executor/models/*.py`
- Any PR that renames fields across `vllm/multimodal/processing/` and `vllm/benchmarks/`

# OpenAI API Protocol: Prefer Pydantic-Native Validation

## Pattern

In the OpenAI-compatible API protocol layer (`vllm/entrypoints/openai/`),
**use Pydantic-native field constraints** (`Field(ge=0)`, `Field(le=...)`,
`Annotated[int, Field(...)]`) instead of writing custom `model_validator`
methods for simple input validation.

Custom validators are verbose, error-prone (easy to miss edge cases in
nested types), and harder to maintain. Pydantic constraints are declarative,
apply automatically to nested types, and produce clear error messages.

## What to look for

- New or modified `model_validator` methods in protocol files — could the
  validation be expressed as a `Field()` constraint on the type annotation?
- Prompt fields accepting `list[int]` or `list[list[int]]` — token IDs
  should use `Annotated[int, Field(ge=0)]`
- Any numeric field where negative values are invalid — prefer `Field(ge=0)`
  over a custom check

## Example

```python
# Bad: custom validator for a simple constraint
@model_validator(mode="before")
@classmethod
def validate_prompt_token_ids(cls, data):
    prompt = data.get("prompt")
    # ... 20 lines of nested isinstance checks ...

# Good: Pydantic-native constraint
prompt: list[Annotated[int, Field(ge=0)]] | list[list[Annotated[int, Field(ge=0)]]] | str | list[str] | None = None
```

## Files to watch

- `vllm/entrypoints/openai/completion/protocol.py`
- `vllm/entrypoints/openai/chat/protocol.py`
- Any `protocol.py` under `vllm/entrypoints/openai/`

## Reviewer behavior

- `DarkLight1337`: Approves clean validation fixes quickly when they follow
  Pydantic conventions and include tests.
- PRs that convert 500 errors to proper 400 validation errors are welcomed,
  especially when discovered via fuzz testing.

## Evidence

- PR #35231: Author initially wrote a verbose custom `model_validator` for
  negative token ID checks, then replaced it with `Annotated[int, Field(ge=0)]`
  on the type annotation. Approved and merged quickly.

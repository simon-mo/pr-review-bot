# Large Refactor Review Expectations

## Pattern
vLLM maintainers expect even internal refactoring PRs to clearly justify their purpose and document new abstractions. Reviewers will question "what problem are we solving?" even for PRs authored by other maintainers.

## What to look for

### 1. Missing motivation for pure refactors
If a PR is purely restructuring code without fixing a bug or adding a feature, reviewers expect explicit justification of what's being simplified and why. A PR that says "decouple X from Y" without explaining the concrete problem will get pushback.

### 2. New dataclasses/classes without docstrings
When a refactor introduces new abstractions (dataclasses, context objects, registries), reviewers ask for descriptions even on internal-only types. A bare `@dataclass` with no docstring will get flagged.

### 3. Benchmark proof for performance-labeled refactors
If a refactor is labeled `performance` or claims to not regress performance, reviewers expect before/after benchmark numbers with the same test setup.

## What to flag
1. Refactoring PRs with no clear "why" beyond "cleaner code" — ask for the concrete problem being solved
2. New classes/dataclasses missing a docstring explaining their purpose
3. PRs labeled `performance` without comparative benchmark results

## Evidence
- **PR #35083**: Member ywang96 asked "I'm a little bit confused by the purpose of this PR - what problem are we trying to address here?" on a 38-file refactor by fellow maintainer DarkLight1337. The author had to explain it was to simplify `InputProcessingContext` and avoid passing `ObservabilityConfig` into the MM registry.
- **PR #35083**: Reviewer reaganjlee asked "Can you add description" on the new `TimingContext` dataclass that had no docstring.

## Reviewer behaviors
- **ywang96**: Questions the purpose of refactoring PRs, wants clear problem statements
- **reaganjlee**: Asks for docstrings/descriptions on new classes, appreciates reduced clutter
- **Isotr0py**: Approves clean refactors without extensive comments

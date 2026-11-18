# ADR-0001: Test each behaviour once, at the lowest level that can prove it

- Status: accepted
- Enforced by: `scripts/test-budget.sh`

## Context

Suites grow by addition. The same behaviour ends up asserted in a unit test, an integration test and an e2e test, each slowing CI and each needing an edit when the behaviour changes.

## Decision

- Unit tests cover logic: branching, validation, error handling, data transformation.
- Integration tests cover only the seam they cross (database, HTTP boundary, external client).
- End-to-end tests cover only a user path no lower level proves.
- A new test names the behaviour it alone covers. If it cannot, it is not added.
- When a higher-level test proves a behaviour a lower one also asserts, delete one of the two. Never keep both. Delete a test only after it is mapped to the remaining test that asserts the same behaviour, with coverage at or above 80% and no new excludes.
- Coverage stays at or above 80%. No threshold is lowered and no exclude is added to make a deletion pass.
- Test lines per 100 source lines stay at or under the budget in `scripts/test-budget.sh` (`TEST_BUDGET_MAX_RATIO`, default 35).

## Consequences

- The suite stays small enough to run unsharded.
- `scripts/test-budget.sh` fails only on the ratio. It reports likely duplicates and never fails on them (a title repeated in a file or across files, near-identical assertions, a unit and an e2e file naming one route or function). Merging them follows the test-consolidate skill.
- A breach is fixed by consolidating tests, never by raising the limit.

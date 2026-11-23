<!-- ref: test/implementation.md
     loaded-by: test/SKILL.md
     prereq: Test agent workflow. Do not invoke this file directly — it is catted by agents via skills/test/SKILL.md (de-registered agent utility). -->

# Test Agent

Write the few tests that protect behaviour you added or changed, run the suite, report. Apply the test-value rule in `docs/CONSTITUTION.md` §4 (migrated projects without it: run `templatecentral:migrate` to add it).

**Called by `templatecentral:scaffold`:** run the existing suite only (step 2) and report `Tests written: none (scaffold run)`. Template code ships with its own tests; do not load `templatecentral:add (test)`.

## Steps

1. For code added or changed this session: list its distinct behaviours, check which existing tests already cover them, extend those, write new tests only for the gap. If not called by `add`, load the stack's test conventions via `templatecentral:add (test)` first
2. Run the suite: `pnpm test` (Next.js / Vite-React / NestJS) or `python -m pytest test/ -q` (FastAPI)
3. Report (see Reporting)

## Dedupe pass

When the suite is slow or large, or when asked: measure with `bash scripts/test-budget.sh -v` (ADR-0001), merge sibling cases into `it.each` / `pytest.mark.parametrize`, and list the tests you propose to delete. Record coverage before (`pnpm test:ci` / `pytest --cov=src`) and re-run after; restore any test whose covered lines or changed-line coverage dropped. Never delete a test of a real code path (branching, validation, error handling, data transformation); a no-value test restates a constant, type or re-export, tests only the framework, or asserts its own mock. Wait for the user's confirmation before deleting any test. Never lower a gate, exclude files or add ignore pragmas to compensate.

## Reporting

```
Test agent — <stack>

Tests written:
- <file> (<n> tests — behaviours covered)
Extended: <file> (<what>)

Suite: <passed> passed, <failed> failed
```

On failure add, per failure: `file:line — test name`, expected vs received, error message. Report only; do not edit files; the caller decides what to fix.

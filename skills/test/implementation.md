<!-- ref: test/implementation.md
     loaded-by: test/SKILL.md
     prereq: Test agent workflow. Do not invoke this file directly — it is catted by agents via skills/test/SKILL.md (de-registered agent utility). -->

# Test Agent

Write the few tests that protect behaviour you added or changed, run the suite, report. Apply the test-value rule in `docs/CONSTITUTION.md` §4 (migrated projects without it: run `templatecentral:migrate` to add it).

**Called by `templatecentral:scaffold`:** run the existing suite only (step 4) and report `Tests written: none (scaffold run)`. Template code ships with its own tests; do not load `templatecentral:add (test)`.

## Stack Detection

Use the build utility's Stack Detection table (`<skill-dir>/../build/implementation.md`).

## Steps

1. Detect stack
2. Load the stack's conventions via `templatecentral:add (test)`
3. For code added or changed this session: list its distinct behaviours, check which existing tests already cover them, extend those, write new tests only for the gap
4. Run the suite:
   - Next.js / Vite-React / NestJS: `pnpm test`
   - FastAPI: `python -m pytest test/ -q`
5. Report (see Reporting)

## Dedupe pass

Run when the suite is slow or large, or when asked. Behaviour stays; case count drops.

1. Measure: case count, runtime, and test-to-source line ratio. Record coverage first (`pnpm test:ci` / `pytest --cov=src`).
2. Find tests exercising the same behaviour: near-identical bodies, same function with one changed input, one assertion per case across a table of inputs, tests that only restate a constant, a type or a re-export, or that only exercise framework code, and mocks asserting themselves. Such tests add no coverage or behaviour value; a test of a real code path (branching, validation, error handling, data transformation) is never in this group.
3. Merge sibling cases into `it.each` / `pytest.mark.parametrize` (no confirmation needed). List the proposed merges and deletions, wait for the user's confirmation before deleting any test, then delete the redundant and no-value tests. Split nothing back out.
4. Re-run coverage. Changed-line coverage and each file's covered lines must not drop; if one does, restore the test that covered them.
5. Report before/after counts and runtime. Never lower a gate, exclude files, or add ignore pragmas to compensate.

## Reporting

```
Test agent — <stack>

Tests written:
- <file> (<n> tests — behaviours covered)
Extended: <file> (<what>)

Suite: <passed> passed, <failed> failed
```

On failure add, per failure: `file:line — test name`, expected vs received, error message. Do not auto-fix failing tests — report only.

## Callers

Dispatched by `templatecentral:add` (`feature`, `endpoint`, and their aliases) and by `templatecentral:scaffold` (post-scaffold check, suite only).

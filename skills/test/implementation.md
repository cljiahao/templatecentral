<!-- ref: test/implementation.md
     loaded-by: test/SKILL.md
     prereq: Test agent workflow. Do not invoke this file directly — it is catted by agents via skills/test/SKILL.md (de-registered agent utility). -->

# Test Agent

Write tests for newly added code using the stack's `templatecentral:add (test)` skill conventions. Run the full test suite. Report failures with context.

## Stack Detection

Use the build utility's Stack Detection table (`<skill-dir>/../build/implementation.md`).

## Steps

1. Detect stack
2. Load the stack's test conventions via `templatecentral:add (test)`
3. Identify code added in this session and write tests for it following those conventions
4. Run the full test suite:
   - Next.js / Vite-React / NestJS: `pnpm test`
   - FastAPI: `python -m pytest test/ -q`
5. Report results (see Reporting below)

## Reporting

**On success:**
```
Test agent — Next.js

Tests written:
- test/api/projects.test.ts (6 tests — GET /api/projects, POST /api/projects, error cases)

Suite: 42 passed, 0 failed
```

**On failure:**
```
Test agent — Next.js

Tests written:
- test/api/projects.test.ts (6 tests)

Suite: 39 passed, 3 failed

Failures:
- test/api/projects.test.ts:34 — POST /api/projects returns 400 on missing name
  Expected: 400
  Received: 500
  Error: Cannot read properties of undefined (reading 'name')
```

Rules:
- List every new test file with test count and brief description
- Every failure: `file:line — test description`, expected vs received, error message
- Do not auto-fix failing tests — report only

## Callers

Dispatched by `templatecentral:add` (`feature`, `endpoint`, and their aliases).
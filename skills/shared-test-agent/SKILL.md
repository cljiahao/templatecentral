---
name: shared-test-agent
description: Use when writing and running tests for newly added code following the stack's test conventions
---

# Test Agent

Write tests for newly added code using the stack's `add-test` skill conventions. Run the full test suite. Report failures with context.

## Stack Detection

Same as `build-agent`: check for `next.config.ts`, `vite.config.ts`, `nest-cli.json`, `requirements.txt` containing `fastapi`.

## Steps

1. Detect stack
2. Load the stack's `add-test` skill:
   - Next.js → `nextjs/add-test`
   - Vite-React → `vite-react/add-test`
   - FastAPI → `fastapi/add-test`
   - NestJS → `nestjs/add-test`
3. Identify newly added code (files written in this session)
4. Write tests following the `add-test` skill conventions
5. Run the full test suite:
   - Next.js / Vite-React / NestJS: `pnpm test`
   - FastAPI: `pytest test/`
6. Report results (see Reporting below)

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

Dispatched by: `nextjs/add-feature`, `nextjs/add-api-route`, `vite-react/add-feature`, `fastapi/add-endpoint`, `nestjs/add-module`.

## Changelog
### 1.0.0
- Initial plugin release

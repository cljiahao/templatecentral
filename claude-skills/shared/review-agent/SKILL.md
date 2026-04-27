---
name: review-agent
description: Use when reviewing newly written code against templateCentral code standards for the detected stack
---

# Review Agent

Review changed files against the stack's code-standards skill. Report violations with `file:line` references. Do not auto-fix.

## Stack Detection

Same as `build-agent`: check for `next.config.ts`, `vite.config.ts`, `nest-cli.json`, `requirements.txt` containing `fastapi`.

## Steps

1. Detect stack
2. Load the stack's `code-standards` skill:
   - Next.js → `nextjs/code-standards`
   - Vite-React → `vite-react/code-standards`
   - FastAPI → `fastapi/code-standards`
   - NestJS → `nestjs/code-standards`
3. Identify changed files (files written or edited in this session)
4. Review each changed file against the code-standards rules
5. Report violations (see Reporting below)

## Reporting

```
Review agent — Next.js

Violations:
- src/features/projects/components/project-card.tsx:12 — default export used; use named export
- src/features/projects/hooks/use-projects.ts:3 — arrow function component; use function declaration
- src/features/projects/api/project-service.ts:45 — raw fetch without APIError wrapper

No violations: src/features/projects/types.ts, src/features/projects/constants.ts
```

Rules:
- Every violation: `file:line — rule description`
- List clean files explicitly
- Do not auto-fix any violation
- Do not suggest how to fix unless the calling skill requests it

## Callers

Dispatched by: `nextjs/add-feature`, `nextjs/add-component`, `nextjs/add-api-route`, `vite-react/add-feature`, `vite-react/add-component`, `fastapi/add-endpoint`, `nestjs/add-module`, `nextjs/add-integration`, `nextjs/add-auth`.

## Changelog
### 1.0.0
- Initial plugin release

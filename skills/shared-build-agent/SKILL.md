---
name: shared-build-agent
description: Use when validating a project compiles after code changes — detects stack from project files and runs the correct build command
---

# Build Agent

Detect project stack, run the appropriate build command, report failures with exact context. Do not auto-fix — report only.

## Stack Detection

Check project root for these files in order:

| File present | Stack |
|---|---|
| `next.config.ts`, `next.config.js`, or `next.config.mjs` | Next.js |
| `vite.config.ts` or `vite.config.js` (no `next.config`) | Vite-React |
| `nest-cli.json` | NestJS |
| `requirements.txt` containing `fastapi` | FastAPI |

If ambiguous (multiple markers), check `package.json` `dependencies` field for `"next"` vs `"vite"` vs `"@nestjs/core"`.

## Build Commands

| Stack | Command |
|---|---|
| Next.js | `pnpm build && pnpm check` |
| Vite-React | `pnpm build && pnpm check` |
| NestJS | `pnpm build` |
| FastAPI | `ruff check src/ && pytest test/` |

## Steps

1. Detect stack (see above)
2. Run the build command for that stack
3. Capture full stdout + stderr
4. Evaluate result:
   - **Success**: report "Build passed" with stack name
   - **Failure**: report failures (see Failure Reporting below)

## Failure Reporting

Extract every error with its exact location. Format:

```
Build failed — Next.js

Errors:
- src/features/auth/components/login-form.tsx:42 — Type 'string' is not assignable to type 'number'
- src/app/api/users/route.ts:18 — Property 'userId' does not exist on type 'Session'

Warnings (non-blocking):
- src/lib/utils/format.ts:7 — 'unused' is declared but never read
```

Rules:
- Every error: `file:line — message` (exact compiler output, not paraphrased)
- Warnings separate from errors
- Do not auto-fix any error
- Do not suggest fixes unless the calling skill requests it
- Report back to the calling skill context — the calling skill decides what to do

## No Stack Detected

If no stack can be determined, report:

```
Build agent: could not detect stack. No next.config.ts/.js/.mjs, vite.config.ts/.js, nest-cli.json, or fastapi in requirements.txt found at project root.
```

Do not attempt to run any build command.

## Callers

This skill is dispatched by: `nextjs-scaffold`, `vite-react-scaffold`, `fastapi-scaffold`, `nestjs-scaffold`, `shared-update-agent`, `nextjs-add-feature`, `nextjs-add-component`, `nextjs-add-api-route`, `vite-react-add-feature`, `vite-react-add-component`, `fastapi-add-endpoint`, `nestjs-add-module`.

## Changelog
### 1.0.0
- Initial plugin release

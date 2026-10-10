<!-- ref: build/implementation.md
     loaded-by: build/SKILL.md
     prereq: Build agent workflow. Do not invoke this file directly — it is catted by agents via skills/build/SKILL.md (de-registered agent utility). -->

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
| NestJS | `pnpm build && pnpm check` |
| FastAPI | `ruff check src/ && python -m pyright src/` |

Running pytest belongs to the test utility (`skills/test/implementation.md`) — do not run it here.

## Steps

Run the stack's command, capturing stdout + stderr. Success → report "Build passed — <stack>". Failure → report as below.

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

Dispatched by `templatecentral:scaffold`, `templatecentral:add`, `templatecentral:migrate`, `templatecentral:standards`, and the review utility (`update` operation).
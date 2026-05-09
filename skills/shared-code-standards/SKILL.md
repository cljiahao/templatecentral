---
name: shared-code-standards
description: Use when writing or reviewing code in any templateCentral project — universal quality + stack-specific standards
---

# Code Standards

## Stack Detection

Check the current project root:

| File present | Stack |
|---|---|
| `requirements.txt` containing `fastapi` | FastAPI |
| `nest-cli.json` | NestJS |
| `next.config.ts`, `next.config.js`, or `next.config.mjs` | Next.js |
| `vite.config.ts` or `vite.config.js` (no `next.config`) | Vite + React |

Apply **Universal Code Quality** first, then load the matching stack section below.

---

## Universal Code Quality (all stacks)

- **YAGNI** — only what the task requires; no speculative helpers or files
- **DRY** — extract at second repetition; inline if only one callsite
- **SRP** — one responsibility per file/function
- **SoC** — routing/HTTP separate from business logic; validation separate from domain logic
- **No premature abstractions** — wait for the third callsite
- **No dead code** — no commented-out code, unused imports, or TODO stubs
- **Validate at boundaries** — Pydantic/Zod for all user input, API responses, and env vars
- **Fail loudly** — no empty catch blocks; log with context; return meaningful HTTP status codes
- **Least privilege** — return only needed fields; never expose raw DB records or internal IDs
- **No secrets** — no hardcoded tokens or keys; env vars only; document in `.env.example`

---

## Stack-Specific Standards

Load the stack-specific coding standards:

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-code-standards/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-code-standards/nestjs.md"
```
Follow the loaded guide exactly.

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-code-standards/nextjs.md"
```
Follow the loaded guide exactly.

**Vite + React:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-code-standards/vite-react.md"
```
Follow the loaded guide exactly.

---
name: shared-add-test
description: Use when adding tests to any templateCentral project — FastAPI (pytest), NestJS (Vitest), Next.js (Vitest API routes), or Vite + React (Vitest + Testing Library).
---

# Add Tests

## Stack Detection

Before starting, identify the project stack:

| Signal file | Stack |
|---|---|
| `requirements.txt` containing `fastapi` | FastAPI |
| `nest-cli.json` | NestJS |
| `next.config.ts` / `next.config.js` / `next.config.mjs` | Next.js |
| `vite.config.ts` / `vite.config.js` (no `next.config.*`) | Vite + React |

Then run the matching `cat` command below and follow the loaded guide:

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-test/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-test/nestjs.md"
```
Follow the loaded guide exactly.

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-test/nextjs.md"
```
Follow the loaded guide exactly.

**Vite + React:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-test/vite-react.md"
```
Follow the loaded guide exactly.

---
name: shared-add-auth
description: Add authentication and route protection to any templateCentral project — FastAPI, NestJS, Next.js, or Vite+React
---

# Add Auth

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
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-auth/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-auth/nestjs.md"
```
Follow the loaded guide exactly.

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-auth/nextjs.md"
```
Follow the loaded guide exactly.

**Vite + React:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-auth/vite-react.md"
```
Follow the loaded guide exactly.

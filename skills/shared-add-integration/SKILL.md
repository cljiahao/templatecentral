---
name: shared-add-integration
description: Use when connecting to an external API (e.g., GitHub, Stripe, OpenAI) from any templateCentral project — FastAPI, NestJS, Next.js, or Vite + React.
---

# Add an External Integration

Create a new third-party API integration in a templateCentral project.

## Stack Detection

Before starting, identify the project stack:

| Signal file | Stack |
|---|---|
| `requirements.txt` containing `fastapi` | FastAPI |
| `nest-cli.json` | NestJS |
| `next.config.ts` / `next.config.js` / `next.config.mjs` | Next.js |
| `vite.config.ts` / `vite.config.js` (no `next.config.*`) | Vite + React |

## Inputs

- **Service name** — The external service (e.g., `github`, `stripe`, `openai`)
- **Base URL** — The API base URL

---

Then run the matching `cat` command below and follow the loaded guide:

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-integration/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-integration/nestjs.md"
```
Follow the loaded guide exactly.

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-integration/nextjs.md"
```
Follow the loaded guide exactly.

**Vite + React:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-integration/vite-react.md"
```
Follow the loaded guide exactly.

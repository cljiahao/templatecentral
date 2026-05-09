---
name: shared-add-database
description: Add a database to any templateCentral project — FastAPI (SQLAlchemy/Beanie), NestJS or Next.js (Drizzle/Kysely/Mongoose).
---

# Add Database

> **Opt-in only**: Do not add database support unless the user explicitly requests it.

## Step 0 — Detect stack and route

Check line 1 of `AGENTS.md` for the templateCentral stack marker:

- `<!-- templateCentral: fastapi@` → run:
  ```bash
  cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/python.md"
  ```
  Follow the loaded guide exactly, then stop.

- `<!-- templateCentral: nestjs@` → run:
  ```bash
  cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript.md"
  ```
  Follow the loaded guide exactly, then stop.

- `<!-- templateCentral: nextjs@` → run:
  ```bash
  cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript.md"
  ```
  Follow the loaded guide exactly, then stop.

- `<!-- templateCentral: vite-react@` → exit. Tell the user: "Database integration is not available for Vite + React — Vite + React projects are client-side SPAs that connect to a backend API. Add a database to the backend service instead."

- No marker found → run `Skill("templatecentral:shared-migrate")` first, then re-check line 1. If the marker is now present, return to the top of Step 0. If still absent, exit.

Do not proceed beyond stack detection — all implementation is handled by the loaded guide.

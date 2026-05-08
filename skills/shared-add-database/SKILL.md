---
name: shared-add-database
description: Use when the user wants to add a database to any templateCentral project — FastAPI (SQLAlchemy/Beanie), NestJS (Drizzle/Kysely/Mongoose), or Next.js (Drizzle/Kysely/Mongoose). Detects stack automatically and routes to the stack-specific implementation.
---

# Add Database

> **Opt-in only**: Do not add database support unless the user explicitly requests it.

## Step 0 — Detect stack and route

Check line 1 of `AGENTS.md` for the templateCentral stack marker:

- `<!-- templateCentral: fastapi@` → invoke `Skill("templatecentral:shared-add-database-python")` and stop
- `<!-- templateCentral: nestjs@` → invoke `Skill("templatecentral:shared-add-database-typescript")` and stop
- `<!-- templateCentral: nextjs@` → invoke `Skill("templatecentral:shared-add-database-typescript")` and stop
- `<!-- templateCentral: vite-react@` → exit. Tell the user: "Database integration is not available for Vite + React — Vite + React projects are client-side SPAs that connect to a backend API. Add a database to the backend service instead."
- No marker found → invoke `Skill("templatecentral:shared-migrate")` first, then re-check line 1. If the marker is now present, return to the top of Step 0. If still absent, exit.

Do not proceed beyond stack detection — all implementation is handled by the dispatched sub-skill.

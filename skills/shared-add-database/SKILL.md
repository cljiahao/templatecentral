---
name: shared-add-database
description: Add a database to any templateCentral project — FastAPI (SQLAlchemy/Beanie), NestJS or Next.js (Drizzle/Kysely/Mongoose).
---

# Add Database

> **Opt-in only**: Do not add database support unless the user explicitly requests it.

## Step 0 — Detect stack and route

Check line 1 of `AGENTS.md` for the marker:

| Marker | Action |
|--------|--------|
| `fastapi@` | Load `python.md` and follow exactly. |
| `nestjs@` or `nextjs@` | Load `typescript.md` and follow exactly. |
| `vite-react@` | Exit: "Database integration is not available for Vite + React — client-side SPAs connect to backend APIs." |
| Not found | Run `Skill("templatecentral:shared-migrate")`, re-check line 1, and return to Step 0 if marker now present. Otherwise exit. |

All implementation is delegated to the loaded guide.

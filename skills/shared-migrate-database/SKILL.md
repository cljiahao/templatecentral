---
name: shared-migrate-database
description: Upgrade database to AWS IAM authentication — Drizzle/SQLAlchemy to Kysely/SQLAlchemy+IAM (internal use only)
disable-model-invocation: true
---

## Step 0 — Verify existing setup

Detect the project stack and current library:

1. Check `AGENTS.md` line 1 for the stack marker.
2. Check which database files exist:

| Marker | Files present | Migration path |
|---|---|---|
| `fastapi@` | `src/database/session.py` with `create_engine` | FastAPI |
| `nestjs@` | `src/database/drizzle.service.ts` | NestJS |
| `nextjs@` | `src/integrations/database/db-client.ts` | Next.js |

If signals conflict, trust the **file presence check** — the project may have been partially migrated.

If no database setup is found → exit: *"I don't see an existing database setup. Run `shared-add-database` first, then request the migration."*

## Step 1 — Load migration guide

Run the matching command and follow the loaded guide exactly:

- **FastAPI:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-migrate-database/fastapi.md"`
- **NestJS:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-migrate-database/nestjs.md"`
- **Next.js:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-migrate-database/nextjs.md"`

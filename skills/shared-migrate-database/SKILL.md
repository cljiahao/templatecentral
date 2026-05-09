---
name: shared-migrate-database
description: Upgrade an existing database setup from low to high compliance — Drizzle → Kysely + AWS IAM (NestJS/Next.js) or SQLAlchemy basic → SQLAlchemy + AWS IAM (FastAPI). Invoked internally by shared-add-database-python and shared-add-database-typescript.
disable-model-invocation: true
---

# Migrate Database to High Compliance

Upgrades an existing low-compliance database setup to use AWS IAM authentication.

**Out of scope:** SQL ↔ MongoDB, version upgrades, schema data migrations, and any migration not listed below.

## Step 0 — Verify existing setup

Detect the project stack and current library:

1. Check `AGENTS.md` line 1 for the stack marker.
2. Check which database files exist:

| Marker | Files present | Migration path |
|---|---|---|
| `fastapi@` | `src/database/session.py` with `create_engine` | FastAPI |
| `nestjs@` | `src/database/drizzle.service.ts` | NestJS |
| `nextjs@` | `src/integrations/database/db-client.ts` | Next.js |

If no database setup is found → exit. Tell the user: *"I don't see an existing database setup. Run `shared-add-database` first, then request the migration."*

## Step 1 — Load migration guide

Run the matching `cat` command for your stack and follow the loaded guide exactly.

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-migrate-database/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-migrate-database/nestjs.md"
```
Follow the loaded guide exactly.

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-migrate-database/nextjs.md"
```
Follow the loaded guide exactly.

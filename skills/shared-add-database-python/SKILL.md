---
name: shared-add-database-python
description: FastAPI database setup — SQLAlchemy (SQL low or high compliance) or Beanie (MongoDB). Invoked by shared-add-database.
disable-model-invocation: true
---

# Add Database to FastAPI

Add a database to a FastAPI project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it. The base template is intentionally database-free.

## Choose Your Database and Compliance Level

### Step 0 — Detect intent

If the user's request includes "migrate database to compliance", "upgrade database to IAM", "switch to IAM auth", or similar upgrade intent → invoke `Skill("templatecentral:shared-migrate-database")` and stop.

### Step 1 — Database type

Ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

If the user explicitly names a library (`SQLAlchemy`, `Beanie`) → skip to that section directly.

### Step 2 — Compliance level (SQL only, skip for MongoDB)

> **SQLite note:** SQLite is always standard auth — it is file-based and does not support network IAM auth. If the user needs SQLite, use SQLAlchemy (standard).

Scan the conversation for compliance signals:

**High-compliance signals:** `HIPAA`, `PCI`, `PCI-DSS`, `SOC 2`, `fintech`, `healthcare`, `government`, `AWS IAM`, `regulated`, `enterprise`, `compliance requirement`

- Signals found → use SQLAlchemy + AWS IAM
- No signals → ask: *"Is this project for a regulated industry (e.g. healthcare, finance, government) or does it need to connect to AWS RDS using IAM authentication rather than a password?"*
  - **Yes** → SQLAlchemy + AWS IAM
  - **No** → SQLAlchemy (standard)
  - **Not sure** → SQLAlchemy (standard) — a migration path is available later

### Step 3 — Load implementation

Based on your compliance level, run the matching `cat` command and follow the loaded guide exactly.

**SQLAlchemy (standard):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-python/sqlalchemy.md"
```
Follow the loaded guide exactly.

**SQLAlchemy + AWS IAM (high compliance):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-python/sqlalchemy-iam.md"
```
Follow the loaded guide exactly.

**Beanie (MongoDB):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-python/beanie.md"
```
Follow the loaded guide exactly.

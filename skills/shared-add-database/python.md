<!-- ref: shared-add-database/python.md
     loaded-by: shared-add-database/SKILL.md
     prereq: Stack identified as FastAPI/Python. Do not invoke this file directly — it is loaded at runtime by the shared-add-database skill. -->

# Add Database to FastAPI

> **Opt-in only**: Do not add database support unless the user explicitly requests it.

## Step 0 — Detect intent

If the user's request includes "migrate database to compliance", "upgrade database to IAM", or "switch to IAM auth" → stop and say: "Run `shared-migrate-database` to handle that upgrade."

## Step 1 — Database type

Ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

If the user explicitly names a library (`SQLAlchemy`, `Beanie`) → skip to that section directly.

## Step 2 — Compliance level (SQL only, skip for MongoDB)

> **SQLite note:** SQLite is always standard auth — file-based, no network IAM. Use SQLAlchemy (standard).

Scan the conversation for compliance signals: `HIPAA`, `PCI`, `PCI-DSS`, `SOC 2`, `fintech`, `healthcare`, `government`, `AWS IAM`, `regulated`, `enterprise`, `compliance requirement`

- Signals found → use SQLAlchemy + AWS IAM
- No signals → ask: *"Is this for a regulated industry or does it require AWS RDS IAM authentication?"*
  - **Yes** → SQLAlchemy + AWS IAM
  - **No** → SQLAlchemy (standard)
  - **Not sure** → SQLAlchemy (standard) — migration path available later

## Step 3 — Load implementation

**SQLAlchemy (standard):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/python/sqlalchemy.md"
```

**SQLAlchemy + AWS IAM (high compliance):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/python/sqlalchemy-iam.md"
```

**Beanie (MongoDB):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/python/beanie.md"
```

Follow the loaded guide exactly.

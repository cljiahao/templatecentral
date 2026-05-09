<!-- ref: shared-add-database/python.md
     loaded-by: shared-add-database/SKILL.md
     prereq: Stack identified as FastAPI/Python. Do not invoke this file directly — it is loaded at runtime by the shared-add-database skill. -->

# Python Database Stack Router

Detect intent and ask for database type. If migration intent detected ("migrate/upgrade to IAM"), exit and say "Run `shared-migrate-database`."

Ask: *"SQL (PostgreSQL, MySQL, SQLite) or MongoDB?"* — skip if user named a library.

For SQL, detect compliance signals (`HIPAA`, `PCI`, `regulated`, etc.) or ask about IAM. SQLite always uses standard auth.

| Library | Use case | Load |
|---------|----------|------|
| SQLAlchemy | SQL (standard auth) | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/python/sqlalchemy.md"` |
| SQLAlchemy IAM | SQL (AWS IAM auth) | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/python/sqlalchemy-iam.md"` |
| Beanie | MongoDB | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/python/beanie.md"` |

Run the chosen command and follow the loaded guide exactly.

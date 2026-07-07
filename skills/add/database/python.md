<!-- ref: add/database/python.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as FastAPI/Python. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Python Database Stack Router

Detect intent and ask for database type. If migration intent detected ("migrate/upgrade to IAM"), exit and say "Run `templatecentral:migrate`."

Ask: *"SQL (PostgreSQL, MySQL, SQLite) or MongoDB?"* — skip if user named a library.

For SQL, detect high-security signals (`regulated`, `iam`, `no-password`, `audit-logging`, etc.) or ask. SQLite always uses standard auth.

> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

| Library | Use case | Load |
|---------|----------|------|
| SQLAlchemy | SQL (standard auth) | `cat "<skill-dir>/database/python/sqlalchemy.md"` |
| SQLAlchemy IAM | SQL (AWS IAM auth) | `cat "<skill-dir>/database/python/sqlalchemy-iam.md"` |
| Beanie | MongoDB | `cat "<skill-dir>/database/python/beanie.md"` |

Run the chosen command and follow the loaded guide exactly.

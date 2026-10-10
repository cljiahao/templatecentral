<!-- ref: add/database/python.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as FastAPI/Python. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Python Database Stack Router

Detect intent and ask for database type. If migration intent detected ("migrate/upgrade to IAM"), exit and say "Run `templatecentral:migrate`."

Ask: *"SQL (PostgreSQL, MySQL, SQLite) or MongoDB?"* — skip if user named a library.

For SQL, detect high-security signals (`regulated`, `iam`, `no-password`, `audit-logging`, etc.) or ask. SQLite always uses standard auth.

For MongoDB, default to PyMongo async (`AsyncMongoClient`, stays on Python 3.14). Load Beanie only when the user explicitly asks for Beanie or an ODM — and warn first: Beanie does not support Python 3.14 yet, so that path pins the project to Python 3.13 (Beanie guide B0). Never add Motor (deprecated) or ODMantic (requires Motor).

> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

| Library | Use case | Load |
|---------|----------|------|
| SQLAlchemy | SQL (standard auth) | `cat "<skill-dir>/database/python/sqlalchemy.md"` |
| SQLAlchemy IAM | SQL (AWS IAM auth) | `cat "<skill-dir>/database/python/sqlalchemy-iam.md"` |
| PyMongo async | MongoDB (default) | `cat "<skill-dir>/database/python/pymongo-async.md"` |
| Beanie | MongoDB ODM — explicit opt-in only; pins Python 3.13 | `cat "<skill-dir>/database/python/beanie.md"` |

**PyMongo async add-on** — load alongside `pymongo-async.md` only when it applies (sibling leaf; never skip the base guide):

| Condition | Also load |
|-----------|-----------|
| `src/api/services/auth_service.py` exists (auth stubs from `templatecentral:add` auth) | `cat "<skill-dir>/database/python/pymongo-async-auth.md"` |

Run the chosen command(s) and follow the loaded guide(s) exactly.

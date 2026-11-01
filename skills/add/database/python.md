<!-- ref: add/database/python.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as FastAPI/Python. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Python Database Stack Router

Migration intent ("migrate/upgrade to IAM") → stop and say "Run `templatecentral:migrate`."

Ask *"SQL (PostgreSQL, MySQL, SQLite) or MongoDB?"* unless the user named a library.

For SQL, detect high-security signals (`regulated`, `iam`, `no-password`, `audit-logging`, etc.) or ask. SQLite always uses standard auth.

MongoDB defaults to PyMongo async (stays on Python 3.14). Load Beanie only when the user explicitly asks for Beanie or an ODM, warning first that it pins Python 3.13 (Beanie B0). Never add Motor (deprecated) or ODMantic (needs Motor).

| Library | Use case | Load |
|---|---|---|
| SQLAlchemy | SQL (standard auth) | `cat "<skill-dir>/database/python/sqlalchemy.md"` |
| SQLAlchemy IAM | SQL (AWS IAM auth) | `cat "<skill-dir>/database/python/sqlalchemy-iam.md"` |
| PyMongo async | MongoDB (default) | `cat "<skill-dir>/database/python/pymongo-async.md"` |
| Beanie | MongoDB ODM — explicit opt-in only; pins Python 3.13 | `cat "<skill-dir>/database/python/beanie.md"` |

**PyMongo async add-on** — load with `pymongo-async.md` only when it applies (never skip the base guide):

| Condition | Also load |
|---|---|
| `src/api/services/auth_service.py` exists | `cat "<skill-dir>/database/python/pymongo-async-auth.md"` |

Run the chosen `cat`(s); follow the guide(s) exactly.

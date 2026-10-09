<!-- ref: add/database/python/sqlalchemy-iam.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = SQLAlchemy + AWS IAM (high compliance, PostgreSQL only). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI + SQLAlchemy + AWS IAM (High Compliance)

> **Supported databases:** PostgreSQL only (the engine uses the `psycopg` (psycopg 3) driver with boto3-signed tokens — MySQL with IAM requires a different driver and SSL setup not covered here).

### A1. Install Dependencies

Add to `requirements.txt`:

```
sqlalchemy
alembic
boto3
psycopg[binary]
```

### A2. Create Database Base

**`src/database/base.py`**:

```python
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
```

### A3. Initialize Alembic (same as standard)

Run from the **repo root** (not `src/`):

```bash
alembic init alembic
```

Edit `alembic.ini` — set `prepend_sys_path` and **leave `sqlalchemy.url` blank**:

```ini
prepend_sys_path = src
sqlalchemy.url =
```

> **Important**: All `alembic` commands must be run from the **repo root** (where `alembic.ini` lives), not from `src/`.

### A4. Create `src/database/session.py` (IAM variant)

```python
from collections.abc import Generator

import boto3
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from core.config import api_settings


def _get_iam_token() -> str:
    try:
        client = boto3.client("rds", region_name=api_settings.AWS_REGION)
        return client.generate_db_auth_token(
            DBHostname=api_settings.DATABASE_HOST,
            Port=api_settings.DATABASE_PORT,
            DBUsername=api_settings.DATABASE_USER,
        )
    except Exception as exc:
        raise RuntimeError(f"Failed to generate RDS IAM token: {exc}") from exc


engine = create_engine(
    f"postgresql+psycopg://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}",
    # verify-full (not "require") — the IAM auth token is a ~15-minute bearer
    # credential, so the server certificate must be verified against the AWS
    # RDS CA bundle or an on-path attacker can intercept it.
    connect_args={"sslmode": "verify-full", "sslrootcert": api_settings.RDS_CA_BUNDLE_PATH},
)


@event.listens_for(engine, "do_connect")
def provide_token(dialect, conn_rec, cargs, cparams):
    cparams["password"] = _get_iam_token()


SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

### A5. Add IAM fields to `src/core/config.py`

Add these fields to `APISettings` (do not add `DATABASE_URL` — IAM uses separate host/user fields):

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    DATABASE_HOST: str = Field(description="RDS instance hostname")
    DATABASE_PORT: int = Field(default=5432, description="RDS port")
    DATABASE_USER: str = Field(description="IAM database user")
    DATABASE_NAME: str = Field(description="Database name")
    AWS_REGION: str = Field(default="us-east-1", description="AWS region for RDS signer")
    RDS_CA_BUNDLE_PATH: str = Field(description="Path to the AWS global RDS CA bundle used for sslmode=verify-full")
```

Add to `src/.env` (local secrets — never commit) and document in `src/.env.default`:

```
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
AWS_REGION=us-east-1
# AWS global RDS CA bundle — download from
# https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
RDS_CA_BUNDLE_PATH=/path/to/global-bundle.pem
```

### A6. Update `alembic/env.py` for IAM fields

In `alembic/env.py`, replace the `set_main_option` call with:

```python
from core.config import api_settings

sqlalchemy_url = (
    f"postgresql+psycopg://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}"
)
config.set_main_option("sqlalchemy.url", sqlalchemy_url)
```

This URL carries no password, so online migrations must connect through the shared `engine` from `database.session` — it holds the `do_connect` token listener and `verify-full` TLS. A fresh `engine_from_config()` (the `alembic init` default) would fail authentication:

```python
from database.session import engine


def run_migrations_online():
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
```

### A7. Create a Model

**`src/models/project.py`** (example — a generic entity; the `User` model comes from Step A of the auth integration section below):

```python
from uuid import uuid4

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from database.base import Base


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid4()))
    name: Mapped[str] = mapped_column(String, index=True)
    description: Mapped[str] = mapped_column(String)
```

### A8. Generate First Migration

```bash
alembic revision --autogenerate -m "create projects table"
alembic upgrade head
```

### A9. Usage

Inject the session via `Depends(get_db)` and serialize through a Pydantic `response_model` (create `ProjectResponse` in `api/schemas/response/`):

```python
from collections.abc import Sequence

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from api.schemas.response.project import ProjectResponse
from database.session import get_db
from models.project import Project

@router.get("/projects", response_model=list[ProjectResponse])
def list_projects(db: Session = Depends(get_db)) -> Sequence[Project]:
    stmt = select(Project)
    return db.scalars(stmt).all()
```

> **Sync vs async**: Use `def` (not `async def`) for handlers that use sync SQLAlchemy — FastAPI runs `def` handlers in a thread pool; an `async def` handler would block the event loop on every query.
>
> **Important**: Never return raw ORM objects directly — always use `response_model` with a Pydantic schema.

### A10. Validate

```bash
python -m pytest test/ -q
```

Confirm all tests pass.

---

## Completing Auth Integration (SQLAlchemy + IAM)

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations.

The repository, service, and router wiring is **identical** to the standard SQLAlchemy path — only the session/config setup differs (sections A2–A6 above). Load `cat "<skill-dir>/database/python/sqlalchemy.md"` and apply its "Completing Auth Integration" steps exactly as written:

- **Step A** — Create `src/models/user.py`
- **Step B** — Create `src/api/repositories/user_repository.py`
- **Step C** — Replace stubs in `src/api/services/auth_service.py`
- **Step D** — Replace `src/api/routers/auth.py`

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- Place ORM models in `src/models/` — not in `api/`.
- `database/` holds infrastructure only (Base, session, engine) — no business logic.
- Keep IAM fields (`DATABASE_HOST`, `DATABASE_USER`, etc.) in `src/.env` — NEVER hardcode production credentials.
- Always use Alembic for schema changes — never call `Base.metadata.create_all()` in production.
- IAM tokens are short-lived — the `do_connect` event listener ensures a fresh token is fetched for each new connection.
- **PostgreSQL only** for IAM auth — SQLite and MySQL require different approaches not covered here.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
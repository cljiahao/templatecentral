<!-- ref: add/database/python/sqlalchemy-iam.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = SQLAlchemy + AWS IAM (high compliance, PostgreSQL only). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI + SQLAlchemy + AWS IAM (High Compliance)

> **PostgreSQL only** — `psycopg` 3 with boto3-signed tokens; MySQL IAM needs a different driver and is not covered.

### A1. Install Dependencies

Add to `requirements.txt`:

```
sqlalchemy
alembic
boto3
psycopg[binary]
```

### A2. Create Database Base

Run `TC_PART=leaf TC_LEAF=add/database/python/sqlalchemy-iam bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/python/sqlalchemy-iam/template/` (listed in `<skill-dir>/database/python/sqlalchemy-iam/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`src/database/base.py`**:

Copied verbatim from `<skill-dir>/database/python/sqlalchemy-iam/template/src/database/base.py` by the copy step; do not re-type it.

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

> **Important**: run every `alembic` command from the **repo root**, not `src/`.

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
    connect_args={
        "sslmode": "verify-full",
        "sslrootcert": api_settings.RDS_CA_BUNDLE_PATH,
    },
)


@event.listens_for(engine, "do_connect")
def provide_token(dialect, conn_rec, cargs, cparams):
    cparams["password"] = _get_iam_token()


SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def get_db() -> Generator[Session]:
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
    AWS_REGION: str = Field(
        default="us-east-1", description="AWS region for RDS signer"
    )
    RDS_CA_BUNDLE_PATH: str = Field(
        description="Path to the AWS global RDS CA bundle used for sslmode=verify-full"
    )
```

Pyright flags `api_settings = APISettings()` for required env fields; keep (or add) its `# pyright: ignore[reportCallIssue]`.

Add to `src/.env` (never commit) and document in `src/.env.default`:

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

CI has no `src/.env` and `session.py` builds the engine at import, so seed placeholders in **`test/conftest.py`** next to the other `os.environ.setdefault` lines (conftest shape: add (auth) Step 11). Tests override `get_db`, so nothing connects:

```python
for key in ("DATABASE_HOST", "DATABASE_USER", "DATABASE_NAME", "RDS_CA_BUNDLE_PATH"):
    os.environ.setdefault(key, "test-placeholder")
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
from database.base import Base
from database.session import engine

# Autogenerate only sees tables whose model modules were imported — list every one.
from models import project  # noqa: F401

target_metadata = Base.metadata


def run_migrations_online():
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
```

### A7. Create a Model

**`src/models/project.py`** (example entity; `User` comes from the auth section below):

```python
from datetime import datetime
from uuid import uuid4

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from database.base import Base


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(
        String, primary_key=True, default=lambda: str(uuid4())
    )
    name: Mapped[str] = mapped_column(String, index=True)
    description: Mapped[str | None] = mapped_column(String)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
```

### A8. Generate First Migration

```bash
alembic revision --autogenerate -m "create projects table"
alembic upgrade head
```

### A9. Usage

Inject `Annotated[Session, Depends(get_db)]` and serialize through a `response_model` (`ProjectResponse` in `api/schemas/response/`):

```python
from collections.abc import Sequence
from typing import Annotated

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from api.schemas.response.project import ProjectResponse
from database.session import get_db
from models.project import Project


@router.get("/projects", response_model=list[ProjectResponse])
def list_projects(db: Annotated[Session, Depends(get_db)]) -> Sequence[Project]:
    stmt = select(Project)
    return db.scalars(stmt).all()
```

> **Sync vs async**: handlers using sync SQLAlchemy are `def`, not `async def` — an `async def` body blocks the event loop on every query.
>
> **Important**: never return raw ORM objects — use `response_model`.

### A10. Validate

```bash
python -m pytest test/ -q
```

Confirm all tests pass.

---

## Completing Auth Integration (SQLAlchemy + IAM)

> **Only if `templatecentral:add` (auth) ran first** — replaces its 501 stubs with database-backed code.

Repository, service and router wiring is **identical** to standard SQLAlchemy (only A2–A6 differ). Load `cat "<skill-dir>/database/python/sqlalchemy.md"` and apply its "Completing Auth Integration" steps exactly:

- **Step A** — Create `src/models/user.py`
- **Step B** — Create `src/api/repositories/user_repository.py`
- **Step C** — Replace stubs in `src/api/services/auth_service.py`
- **Step D** — Replace `src/api/routers/auth.py`

---

## Rules

- **Opt-in only** — add a database only on request.
- Place ORM models in `src/models/` — not in `api/`.
- `database/` holds infrastructure only (Base, session, engine) — no business logic.
- Keep IAM fields (`DATABASE_HOST`, `DATABASE_USER`, etc.) in `src/.env` — NEVER hardcode production credentials.
- Always use Alembic for schema changes — never call `Base.metadata.create_all()` in production.
- IAM tokens are short-lived — `do_connect` fetches a fresh one per connection.
- **PostgreSQL only** for IAM auth.

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.
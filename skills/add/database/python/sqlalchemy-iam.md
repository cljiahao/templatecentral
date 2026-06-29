<!-- ref: add/database/python/sqlalchemy-iam.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = SQLAlchemy + AWS IAM (high compliance, PostgreSQL only). Do not invoke this file directly. -->
## FastAPI + SQLAlchemy + AWS IAM (High Compliance)

> **Supported databases:** PostgreSQL only (the IAM token signer uses `psycopg2` — MySQL with IAM requires a different driver and SSL setup not covered here).

### A1. Install Dependencies

Add to `requirements.txt`:

```
sqlalchemy
alembic
boto3
psycopg2-binary
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
    f"postgresql+psycopg2://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}",
    connect_args={"sslmode": "require"},
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
```

Add to `src/.env` (local secrets — never commit) and document in `src/.env.default`:

```
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
AWS_REGION=us-east-1
```

### A6. Update `alembic/env.py` for IAM fields

In `alembic/env.py`, replace the `set_main_option` call with:

```python
from core.config import api_settings

sqlalchemy_url = (
    f"postgresql+psycopg2://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}"
)
config.set_main_option("sqlalchemy.url", sqlalchemy_url)
```

### A7. Create a Model

**`src/models/user.py`** (example):

```python
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import String

from database.base import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    email: Mapped[str] = mapped_column(String, unique=True, index=True)
    name: Mapped[str] = mapped_column(String)
    hashed_password: Mapped[str] = mapped_column(String)
```

### A8. Generate First Migration

```bash
alembic revision --autogenerate -m "create users table"
alembic upgrade head
```

### A9. Usage

Inject the database session via FastAPI's dependency injection:

```python
from collections.abc import Sequence

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from api.schemas.response.user import UserResponse  # create this schema
from database.session import get_db
from models.user import User

@router.get("/users", response_model=list[UserResponse])
def list_users(db: Session = Depends(get_db)) -> Sequence[User]:
    stmt = select(User)
    return db.scalars(stmt).all()
```

> **Sync vs async**: Use `def` (not `async def`) for handlers that use sync SQLAlchemy — FastAPI runs `def` handlers in a thread pool, keeping the event loop free.
>
> **Important**: Never return raw ORM objects directly — always use `response_model` with a Pydantic schema.

### A10. Validate

```bash
pytest test/
```

Confirm all tests pass.

---

## Completing Auth Integration (SQLAlchemy + IAM)

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations. The auth wiring is identical to the standard SQLAlchemy path — only the session/config setup differs (already handled above).

The repository, service, and router wiring is **identical** to the standard SQLAlchemy path — only the session/config setup differs (already handled in sections A2–A6 above). Apply these steps from `add/database/python/sqlalchemy.md`, exactly as written there:

- **Step A** — Create `src/models/user.py`
- **Step B** — Create `src/api/repositories/user_repository.py`
- **Step C** — Replace stubs in `src/api/services/auth_service.py`
- **Step D** — Replace `src/api/routers/auth.py`

> **Sync vs async**: Use `def` (not `async def`) for handlers that use sync SQLAlchemy — FastAPI runs `def` handlers in a thread pool, keeping the event loop free.

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
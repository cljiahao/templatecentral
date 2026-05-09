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

### A5. Initialize Alembic (same as standard)

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

### A-IAM.2 — Create `src/database/session.py` (IAM variant)

```python
from collections.abc import Generator

import boto3
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from core.config import api_settings


def _get_iam_token() -> str:
    client = boto3.client("rds", region_name=api_settings.AWS_REGION)
    return client.generate_db_auth_token(
        DBHostname=api_settings.DATABASE_HOST,
        Port=api_settings.DATABASE_PORT,
        DBUsername=api_settings.DATABASE_USER,
    )


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

### A-IAM.3 — Add IAM fields to `src/core/config.py`

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

### A-IAM.4 — Update `alembic/env.py` for IAM fields

In `alembic/env.py`, replace the `set_main_option` call with:

```python
from core.config import api_settings

sqlalchemy_url = (
    f"postgresql+psycopg2://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}"
)
config.set_main_option("sqlalchemy.url", sqlalchemy_url)
```

### A6. Create a Model

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

### A7. Generate First Migration

```bash
alembic revision --autogenerate -m "create users table"
alembic upgrade head
```

### A8. Usage

Inject the database session via FastAPI's dependency injection:

```python
from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from api.schemas.response.user import UserResponse  # create this schema
from database.session import get_db
from models.user import User

@router.get("/users", response_model=list[UserResponse])
def list_users(db: Session = Depends(get_db)) -> list[UserResponse]:
    stmt = select(User)
    return db.scalars(stmt).all()
```

> **Important**: Never return raw ORM objects directly — always use `response_model` with a Pydantic schema.

### A9. Validate

```bash
pytest test/
```

Confirm all tests pass.

---

## Completing Auth Integration (SQLAlchemy + IAM)

> **Only apply this section if `fastapi-add-auth` was run before this skill.** It replaces the 501 stubs with real database-backed implementations. The auth wiring is identical to the standard SQLAlchemy path — only the session/config setup differs (already handled above).

### Step A — Create `src/models/user.py`

```python
from datetime import datetime
from uuid import uuid4

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from database.base import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid4()))
    email: Mapped[str] = mapped_column(String, unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String)
    name: Mapped[str] = mapped_column(String)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```

### Step B — Create `src/api/repositories/user_repository.py`

> Create the `api/repositories/` directory if it does not already exist.

```python
from sqlalchemy import select
from sqlalchemy.orm import Session

from models.user import User


def get_user_by_email(db: Session, email: str) -> User | None:
    return db.scalars(select(User).where(User.email == email)).first()


def get_user_by_id(db: Session, user_id: str) -> User | None:
    return db.scalars(select(User).where(User.id == user_id)).first()


def create_user(db: Session, email: str, hashed_password: str, name: str) -> User:
    user = User(email=email, hashed_password=hashed_password, name=name)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
```

### Step C — Replace stubs in `src/api/services/auth_service.py`

```python
from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from api.repositories.user_repository import create_user, get_user_by_email, get_user_by_id
from core.security import create_access_token, hash_password, verify_password


def register_user(db: Session, email: str, password: str, name: str) -> dict:
    if get_user_by_email(db, email):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        )
    user = create_user(
        db=db,
        email=email,
        hashed_password=hash_password(password),
        name=name,
    )
    return {"id": str(user.id), "email": user.email, "name": user.name}


def login_user(db: Session, email: str, password: str) -> str:
    user = get_user_by_email(db, email)
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
        )
    return create_access_token(subject=str(user.id))


def get_user(db: Session, user_id: str) -> dict:
    user = get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )
    return {"id": str(user.id), "email": user.email, "name": user.name}
```

### Step D — Replace `src/api/routers/auth.py`

```python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from api.dependencies.auth import get_current_user
from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import login_user, register_user, get_user
from database.session import get_db

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=UserResponse)
def register(body: RegisterRequest, db: Session = Depends(get_db)) -> UserResponse:
    """Register a new user account."""
    user = register_user(db=db, email=body.email, password=body.password, name=body.name)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = login_user(db=db, email=body.email, password=body.password)
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
def get_me(user_id: str = Depends(get_current_user), db: Session = Depends(get_db)) -> UserResponse:
    """Get the current authenticated user."""
    user = get_user(db=db, user_id=user_id)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])
```

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
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

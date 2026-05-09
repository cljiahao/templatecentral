<!-- ref: shared-migrate-database/fastapi.md
     loaded-by: shared-migrate-database/SKILL.md
     prereq: Stack = FastAPI. Do not invoke this file directly — it is loaded at runtime by the shared-migrate-database skill. -->
## FastAPI Database Migration

Migrates an existing SQLAlchemy (password auth) setup to SQLAlchemy + AWS IAM authentication.

This is a **config-only change** — no schema or query code changes needed.

### Step 1 — Install boto3

Add to `requirements.txt`:

```
boto3
```

### Step 2 — Replace `src/database/session.py`

Replace the file contents with:

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

### Step 3 — Update `src/core/config.py`

Remove `DATABASE_URL` from `APISettings` and replace with IAM fields:

```python
class APISettings(BaseSettings):
    # ... existing fields (keep all non-database fields) ...
    DATABASE_HOST: str = Field(description="RDS instance hostname")
    DATABASE_PORT: int = Field(default=5432, description="RDS port")
    DATABASE_USER: str = Field(description="IAM database user")
    DATABASE_NAME: str = Field(description="Database name")
    AWS_REGION: str = Field(default="us-east-1", description="AWS region for RDS signer")
```

### Step 4 — Update `alembic/env.py`

Replace the `set_main_option` call:

```python
from core.config import api_settings

sqlalchemy_url = (
    f"postgresql+psycopg2://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}"
)
config.set_main_option("sqlalchemy.url", sqlalchemy_url)
```

### Step 5 — Update `src/.env` and `src/.env.default`

Remove `DATABASE_URL`. Add:

```
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
AWS_REGION=us-east-1
```

### Step 6 — Validate

```bash
pytest test/
```

All tests should pass. If the app starts and connects, the migration is complete.

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

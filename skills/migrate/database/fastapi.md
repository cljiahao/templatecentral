<!-- ref: migrate/database/fastapi.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## FastAPI Database Migration

Moves SQLAlchemy password auth to AWS IAM auth. The app side is **config-only** (no schema or query changes). The Step 0 AWS prerequisites are not optional: without them connect fails with an opaque `PAM authentication failed`.

### Step 0 — Prerequisites (AWS side, before any code change)

Confirm all four with the user; this skill cannot do them:

1. **IAM database authentication is enabled on the RDS instance** — `aws rds modify-db-instance --db-instance-identifier <id> --enable-iam-database-authentication --apply-immediately` (Aurora: `modify-db-cluster`).
2. **The database user is IAM-enabled** — connect as a master user and run `GRANT rds_iam TO <user>;` (PostgreSQL). A user without the `rds_iam` role will reject every IAM token.
3. **The application's IAM principal has an `rds-db:connect` policy** — resource ARN `arn:aws:rds-db:<region>:<account-id>:dbuid:<db-resource-id>/<db-user>`. The DB resource id is not the instance identifier — read it from `aws rds describe-db-instances`.

4. **Download the AWS global RDS CA bundle** to a path readable by the app (needed for `sslmode=verify-full` in Step 2):

```bash
curl -o /path/to/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

### Step 1 — Install boto3 + psycopg 3

Add to `requirements.in`, then run `uv pip compile requirements.in --universal --generate-hashes -o requirements.txt` and `pip install --require-hashes -r requirements.txt`:

```
boto3
psycopg[binary]
```

If `requirements.in` still lists `psycopg2-binary`, replace it — the engine URL below uses the psycopg 3 `postgresql+psycopg://` scheme.

### Step 2 — Replace `src/database/session.py`

Replace the file contents with:

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
    # verify-full, not "require": the IAM token is a bearer credential, so verify the server certificate against the RDS CA bundle.
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

### Step 3 — Update `src/core/config.py`

Remove `DATABASE_URL` from `APISettings` and replace with IAM fields:

```python
class APISettings(BaseSettings):
    # ... keep all existing non-database fields ...
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

### Step 4 — Update `alembic/env.py`

Replace the `set_main_option` call:

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

### Step 5 — Update `src/.env` and `src/.env.default`

Update `src/.env.default` yourself. For `src/.env`, **ask the user** to remove `DATABASE_URL` and add the variables below — agent edits to `.env` files are hook-blocked by design; never write that file directly.

```
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
AWS_REGION=us-east-1
# AWS global RDS CA bundle — downloaded in Step 0
RDS_CA_BUNDLE_PATH=/path/to/global-bundle.pem
```

### Step 6 — Validate

```bash
python -m pytest test/ -q
```

All tests pass and the app connects.

## After Writing Code

Run the project's check command (`ruff check src/ && python -m pyright src/`), then the review utility (`<skill-dir>/../review/SKILL.md`).

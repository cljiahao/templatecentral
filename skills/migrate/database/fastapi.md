<!-- ref: migrate/database/fastapi.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## FastAPI Database Migration

Migrates an existing SQLAlchemy (password auth) setup to SQLAlchemy + AWS IAM authentication.

On the application side this is a **config-only change** — no schema or query code changes needed. The AWS-side prerequisites in Step 0 are not optional: without them the app fails at connect time with an opaque `PAM authentication failed` error.

> **Canonical source**: the session module (Step 2) and `alembic/env.py` block (Step 4) below
> are duplicated verbatim from `add/database/python/sqlalchemy-iam.md` — treat that file as
> canonical. `scripts/lint-skills.sh` fails the build if the two copies drift, so re-copy
> rather than hand-editing here; the `sslmode` / `sslrootcert` connect args are the reason.

### Step 0 — Prerequisites (AWS side, before any code change)

Confirm all four with the user — this skill cannot do any of them:

1. **IAM database authentication is enabled on the RDS instance** — `aws rds modify-db-instance --db-instance-identifier <id> --enable-iam-database-authentication --apply-immediately` (Aurora: `modify-db-cluster`).
2. **The database user is IAM-enabled** — connect as a master user and run `GRANT rds_iam TO <user>;` (PostgreSQL). A user without the `rds_iam` role will reject every IAM token.
3. **The application's IAM principal has an `rds-db:connect` policy** — resource ARN `arn:aws:rds-db:<region>:<account-id>:dbuid:<db-resource-id>/<db-user>`. The DB resource id is not the instance identifier — read it from `aws rds describe-db-instances`.

4. **Download the AWS global RDS CA bundle** to a path readable by the app (needed for `sslmode=verify-full` in Step 2):

```bash
curl -o /path/to/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

### Step 1 — Install boto3 + psycopg 3

Add to `requirements.txt`:

```
boto3
psycopg[binary]
```

If `requirements.txt` still lists `psycopg2-binary`, replace it — the engine URL below uses the psycopg 3 `postgresql+psycopg://` scheme.

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
    RDS_CA_BUNDLE_PATH: str = Field(description="Path to the AWS global RDS CA bundle used for sslmode=verify-full")
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

All tests should pass. If the app starts and connects, the migration is complete.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
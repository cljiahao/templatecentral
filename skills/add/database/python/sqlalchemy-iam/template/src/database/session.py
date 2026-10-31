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

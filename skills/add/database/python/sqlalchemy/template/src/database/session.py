from collections.abc import Generator

from typing import Any

from sqlalchemy import create_engine, make_url
from sqlalchemy.orm import Session, sessionmaker

from core.config import api_settings, common_settings

url = make_url(api_settings.DATABASE_URL)
# libpq's default sslmode=prefer never verifies the server certificate and silently falls
# back to plaintext. Local Docker Postgres serves no TLS, so only dev skips verify-full.
# `system` = the OS CA store (libpq ≥ 16); a private CA (e.g. the RDS bundle) goes in the
# URL as `?sslrootcert=/path/ca.pem`.
connect_args: dict[str, Any] = {}
if url.get_backend_name() == "postgresql" and common_settings.ENVIRONMENT != "dev":
    connect_args = {
        "sslmode": "verify-full",
        "sslrootcert": url.query.get("sslrootcert", "system"),
    }

engine = create_engine(url, echo=False, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def get_db() -> Generator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

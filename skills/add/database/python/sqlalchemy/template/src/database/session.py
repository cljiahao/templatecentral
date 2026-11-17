from collections.abc import Generator

from typing import Any

from sqlalchemy import create_engine, make_url
from sqlalchemy.orm import Session, sessionmaker

from core.config import api_settings, common_settings

url = make_url(api_settings.DATABASE_URL)
# libpq's default sslmode=prefer silently falls back to plaintext; only dev skips verify-full.
connect_args: dict[str, Any] = {}
if url.get_backend_name() == "postgresql" and common_settings.ENVIRONMENT != "dev":
    connect_args = {
        "sslmode": "verify-full",
        # "system" is the OS CA store and needs libpq >= 16; a private CA goes in ?sslrootcert=.
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

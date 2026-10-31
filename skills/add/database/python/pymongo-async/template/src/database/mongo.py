from typing import Annotated, Any

from fastapi import Depends
from pymongo import AsyncMongoClient
from pymongo.asynchronous.database import AsyncDatabase

from core.config import api_settings, common_settings

_client: AsyncMongoClient[dict[str, Any]] | None = None


async def init_mongo() -> None:
    global _client
    _client = AsyncMongoClient(
        api_settings.MONGODB_URL.get_secret_value(),
        # Outside dev, require TLS (overrides any tls=false in the URL): a non-TLS
        # server fails the boot instead of receiving credentials in plaintext.
        tls=common_settings.ENVIRONMENT != "dev",
        # Surface an unreachable server in seconds, not the 30 s default per request.
        serverSelectionTimeoutMS=5000,
        tz_aware=True,
    )
    # The client connects lazily; ping so a bad URL fails the boot, not the first request.
    await _client.admin.command("ping")


async def close_mongo() -> None:
    global _client
    if _client is not None:
        await _client.close()
        _client = None


def get_db() -> AsyncDatabase[dict[str, Any]]:
    if _client is None:
        raise RuntimeError("MongoDB client not initialised — is the lifespan wired?")
    return _client[api_settings.MONGODB_DB_NAME]


DbDep = Annotated[AsyncDatabase[dict[str, Any]], Depends(get_db)]

from beanie import init_beanie
from pymongo import AsyncMongoClient

from core.config import api_settings, common_settings

mongo_client: AsyncMongoClient | None = None


async def init_mongo() -> None:
    global mongo_client
    mongo_client = AsyncMongoClient(
        api_settings.MONGODB_URL.get_secret_value(),
        # Outside dev, require TLS (overrides any tls=false in the URL): a non-TLS
        # server fails the boot instead of receiving credentials in plaintext.
        tls=common_settings.ENVIRONMENT != "dev",
        serverSelectionTimeoutMS=5000,
        tz_aware=True,
    )
    db = mongo_client[api_settings.MONGODB_DB_NAME]

    from models import DOCUMENT_MODELS

    await init_beanie(database=db, document_models=DOCUMENT_MODELS)


async def close_mongo() -> None:
    global mongo_client
    if mongo_client:
        await mongo_client.close()
        mongo_client = None

import asyncio

from beanie import PydanticObjectId
from fastapi import HTTPException, status
from pymongo.errors import DuplicateKeyError

from api.schemas.request.user import CreateUserRequest
from core.security import hash_password
from models.user import User


async def list_users() -> list[User]:
    return await User.find().to_list()


async def get_user(user_id: PydanticObjectId) -> User | None:
    return await User.get(user_id)


async def create_user(payload: CreateUserRequest) -> User:
    # argon2 is ~100 ms of CPU: off the event loop, or it stalls every request.
    hashed = await asyncio.to_thread(hash_password, payload.password)
    user = User(email=payload.email, name=payload.name, hashed_password=hashed)
    try:
        return await user.insert()
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Email already registered."
        ) from None

import asyncio
from typing import Any

from fastapi import HTTPException, status
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from api.repositories.user_repository import UserRepository
from api.schemas.request.user import CreateUserRequest, UpdateUserRequest
from core.security import hash_password
from models.user import User

type Db = AsyncDatabase[dict[str, Any]]


async def list_users(db: Db, *, limit: int, skip: int) -> list[User]:
    return await UserRepository(db).find_many(limit=limit, skip=skip)


async def get_user(db: Db, user_id: str) -> User:
    user = await UserRepository(db).find_by_id(user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found."
        )
    return user


async def create_user(db: Db, payload: CreateUserRequest) -> User:
    # argon2 is ~100 ms of CPU: off the event loop, or it stalls every request.
    hashed = await asyncio.to_thread(hash_password, payload.password)
    user = User(email=payload.email, name=payload.name, hashed_password=hashed)
    try:
        return await UserRepository(db).insert(user)
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Email already registered."
        ) from None


async def update_user(db: Db, user_id: str, payload: UpdateUserRequest) -> User:
    # exclude_none: an explicit `"name": null` would otherwise $set null and leave a
    # document that no longer validates as User.
    changes = payload.model_dump(exclude_unset=True, exclude_none=True)
    user = await UserRepository(db).update(user_id, changes)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found."
        )
    return user

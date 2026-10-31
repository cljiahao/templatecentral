from collections.abc import Mapping
from typing import Any

from bson import ObjectId
from pydantic import BaseModel
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

MAX_PAGE_SIZE = 100


class BaseRepository[T: BaseModel]:
    model: type[T]
    collection_name: str
    # update() writes only these keys, so a request body can never set
    # hashed_password or smuggle a "$" operator into the update document.
    updatable_fields: frozenset[str] = frozenset()

    def __init__(self, db: AsyncDatabase[dict[str, Any]]) -> None:
        self.collection = db[self.collection_name]

    def _to_model(self, doc: dict[str, Any]) -> T:
        doc["id"] = str(doc.pop("_id"))
        return self.model.model_validate(doc)

    async def find_by_id(self, id_: str) -> T | None:
        # A malformed id is "not found", not a 500 from bson.errors.InvalidId.
        if not ObjectId.is_valid(id_):
            return None
        doc = await self.collection.find_one({"_id": ObjectId(id_)})
        return self._to_model(doc) if doc else None

    async def find_many(self, *, limit: int = 20, skip: int = 0) -> list[T]:
        # Clamped here too, so no caller can load the whole collection into memory.
        limit = max(1, min(limit, MAX_PAGE_SIZE))
        cursor = self.collection.find({}).sort("_id", 1).skip(max(0, skip)).limit(limit)
        return [self._to_model(doc) async for doc in cursor]

    async def insert(self, entity: T) -> T:
        result = await self.collection.insert_one(
            entity.model_dump(by_alias=True, exclude={"id"})
        )
        return entity.model_copy(update={"id": str(result.inserted_id)})

    async def update(self, id_: str, changes: Mapping[str, Any]) -> T | None:
        rejected = changes.keys() - self.updatable_fields
        if rejected:
            raise ValueError(f"Fields not updatable: {sorted(rejected)}")
        if not ObjectId.is_valid(id_):
            return None
        if not changes:
            return await self.find_by_id(id_)
        doc = await self.collection.find_one_and_update(
            {"_id": ObjectId(id_)},
            {"$set": dict(changes)},
            return_document=ReturnDocument.AFTER,
        )
        return self._to_model(doc) if doc else None

    async def delete(self, id_: str) -> bool:
        if not ObjectId.is_valid(id_):
            return False
        result = await self.collection.delete_one({"_id": ObjectId(id_)})
        return result.deleted_count == 1

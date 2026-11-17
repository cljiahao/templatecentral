from api.repositories.base import BaseRepository
from models.user import User


class UserRepository(BaseRepository[User]):
    model = User
    collection_name = "users"
    updatable_fields = frozenset({"name"})

    async def find_by_email(self, email: str) -> User | None:
        doc = await self.collection.find_one({"email": email})
        return self._to_model(doc) if doc else None

    async def ensure_indexes(self) -> None:
        # The unique index, not find-then-insert, stops duplicates under concurrent registration.
        await self.collection.create_index("email", unique=True)

from datetime import UTC, datetime

from pydantic import BaseModel, Field


class User(BaseModel):
    id: str | None = None
    email: str
    name: str
    hashed_password: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

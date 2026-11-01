from pydantic import EmailStr, Field

from api.schemas.base import BaseRequestSchema


class CreateUserRequest(BaseRequestSchema):
    email: EmailStr = Field(description="User email address.")
    name: str = Field(min_length=1, max_length=100, description="Display name.")
    password: str = Field(
        min_length=12, max_length=128, description="12-128 characters."
    )


class UpdateUserRequest(BaseRequestSchema):
    name: str | None = Field(default=None, min_length=1, max_length=100)

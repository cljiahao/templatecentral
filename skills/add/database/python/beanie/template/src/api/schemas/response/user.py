from pydantic import Field

from api.schemas.base import BaseResponseSchema


class UserResponse(BaseResponseSchema):
    id: str = Field(description="User ID.")
    email: str = Field(description="User email.")
    name: str = Field(description="Display name.")

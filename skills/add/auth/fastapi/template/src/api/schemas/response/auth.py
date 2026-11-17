from pydantic import BaseModel, Field

from api.schemas.base import BaseResponseSchema


class TokenResponse(BaseModel):
    """JWT token response — plain BaseModel keeps the OAuth2 snake_case field names."""

    access_token: str = Field(description="JWT access token.")
    token_type: str = Field(default="bearer", description="Token type.")


class UserResponse(BaseResponseSchema):
    """Authenticated user info."""

    id: str = Field(description="User ID.")
    email: str = Field(description="User email.")
    name: str = Field(description="User display name.")

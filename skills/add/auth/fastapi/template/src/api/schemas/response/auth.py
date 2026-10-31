from pydantic import BaseModel, Field

from api.schemas.base import BaseResponseSchema


class TokenResponse(BaseModel):
    """JWT token response — uses plain BaseModel to preserve OAuth2-standard snake_case (RFC 6749)."""

    access_token: str = Field(description="JWT access token.")
    token_type: str = Field(default="bearer", description="Token type.")


class UserResponse(BaseResponseSchema):
    """Authenticated user info."""

    id: str = Field(description="User ID.")
    email: str = Field(description="User email.")
    name: str = Field(description="User display name.")

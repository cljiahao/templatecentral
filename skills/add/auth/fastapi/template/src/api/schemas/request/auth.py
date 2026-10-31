from pydantic import EmailStr, Field

from api.schemas.base import BaseRequestSchema


class RegisterRequest(BaseRequestSchema):
    """Registration request."""

    email: EmailStr = Field(description="User email address.")
    password: str = Field(
        min_length=12,
        max_length=128,
        description=(
            "User password — 12-128 characters (OWASP minimum; the upper bound"
            " caps argon2 hashing cost on this unauthenticated endpoint)."
        ),
    )
    name: str = Field(description="User display name.")


class LoginRequest(BaseRequestSchema):
    """Login request."""

    email: EmailStr = Field(description="User email address.")
    password: str = Field(max_length=128, description="User password.")

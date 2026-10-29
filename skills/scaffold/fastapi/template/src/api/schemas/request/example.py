from pydantic import Field

from api.schemas.base import BaseRequestSchema


class ExampleRequest(BaseRequestSchema):
    """Example request schema."""

    name: str = Field(description="A name to greet.")
    repeat_count: int = Field(default=1, ge=1, le=10, description="Times to repeat.")

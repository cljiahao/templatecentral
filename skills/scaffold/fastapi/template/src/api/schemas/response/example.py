from pydantic import Field

from api.schemas.base import BaseResponseSchema


class ExampleResponse(BaseResponseSchema):
    """Example response schema."""

    message: str = Field(description="The greeting message.")
    items: list[str] = Field(description="Repeated greetings.")

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class BaseSchema(BaseModel):
    """Base schema with common configuration."""

    model_config = ConfigDict(
        extra="forbid",
        from_attributes=True,
        validate_assignment=True,
        validate_default=True,
        populate_by_name=True,
        alias_generator=to_camel,
    )


class BaseRequestSchema(BaseSchema):
    """Base for API request schemas."""


class BaseResponseSchema(BaseSchema):
    """Base for API response schemas — always serializes using camelCase aliases."""

    model_config = ConfigDict(
        extra="forbid",
        from_attributes=True,
        validate_assignment=True,
        validate_default=True,
        populate_by_name=True,
        alias_generator=to_camel,
        serialize_by_alias=True,
    )

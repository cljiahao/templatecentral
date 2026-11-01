# src/api/schemas/request/pagination.py
from pydantic import Field

from api.schemas.base import BaseRequestSchema


class PaginationParams(BaseRequestSchema):
    """Shared query params for every paginated list endpoint."""

    # le caps OFFSET cost — an unbounded page is a cheap DoS lever.
    page: int = Field(
        default=1, ge=1, le=10_000, description="Page number (1-indexed)."
    )
    limit: int = Field(default=10, ge=1, le=100, description="Items per page.")
    sort: str | None = Field(
        default=None,
        max_length=64,
        pattern=r"^(asc|desc)_\w+$",
        description="asc_<field> or desc_<field>.",
    )

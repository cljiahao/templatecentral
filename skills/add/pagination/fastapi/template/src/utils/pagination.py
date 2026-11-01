# src/utils/pagination.py
from typing import Literal, cast

from api.schemas.response.pagination import PaginationMetadata

type SortDirection = Literal["asc", "desc"]


def calculate_offset(page: int, limit: int) -> int:
    return (page - 1) * limit


def create_metadata(page: int, limit: int, total: int) -> PaginationMetadata:
    return PaginationMetadata(page=page, limit=limit, total=total, has_more=page * limit < total)


def parse_sort_param(
    sort: str | None, allowed_fields: set[str]
) -> tuple[str, SortDirection] | None:
    """Return (field, direction) for an allow-listed `asc_<field>`/`desc_<field>`, else None."""
    if not sort:
        return None
    # Split once: field names may themselves contain underscores.
    direction, _, field = sort.partition("_")
    if field not in allowed_fields or direction not in ("asc", "desc"):
        return None
    return field, cast(SortDirection, direction)

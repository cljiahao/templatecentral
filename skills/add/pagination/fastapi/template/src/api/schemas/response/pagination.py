# src/api/schemas/response/pagination.py
from api.schemas.base import BaseResponseSchema


class PaginationMetadata(BaseResponseSchema):
    page: int
    limit: int
    total: int
    has_more: bool


class PaginatedData[T](BaseResponseSchema):
    items: list[T]
    pagination: PaginationMetadata


class PaginatedResponse[T](BaseResponseSchema):
    data: PaginatedData[T]

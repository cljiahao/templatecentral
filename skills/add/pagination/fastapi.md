<!-- ref: add/pagination/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### FastAPI (Python + Pydantic + SQLAlchemy)

> **Prerequisites**
> This skill assumes the FastAPI scaffold from `fastapi-scaffold`. File paths below use
> `src/core/` and `src/api/` matching that scaffold layout.
> **If you're using async SQLAlchemy** (`AsyncSession`), ensure `create_async_engine`
> is configured in your project — the default scaffold uses sync SQLAlchemy.
> For sync SQLAlchemy, replace `AsyncSession` with `Session` and remove `await` from
> database calls.

**1. Reusable Pagination Schema**

```python
# src/core/validation/schemas.py
from pydantic import BaseModel, Field
from typing import Literal

class PaginationParams(BaseModel):
    page: int = Field(default=1, ge=1, description='Page number (1-indexed)')
    limit: int = Field(
        default=10,
        ge=1,
        le=100,
        description='Items per page (max 100)'
    )
    sort: str | None = Field(
        default=None,
        pattern=r'^(asc|desc)_\w+$',
        description='Sort format: asc_fieldName or desc_fieldName'
    )
```

**2. Pagination Response Model**

```python
# src/core/types/pagination.py
from pydantic import BaseModel, Field
from typing import Generic, TypeVar

T = TypeVar('T')

class PaginationMetadata(BaseModel):
    page: int
    limit: int
    total: int
    has_more: bool = Field(..., serialization_alias='hasMore')

class PaginatedData(BaseModel, Generic[T]):
    items: list[T]
    pagination: PaginationMetadata

class PaginatedResponse(BaseModel, Generic[T]):
    data: PaginatedData[T]
```

**3. Pagination Service**

```python
# src/core/pagination/pagination_service.py

class PaginationService:
    """Pagination utilities for consistent pagination across endpoints."""

    @staticmethod
    def calculate_offset(page: int, limit: int) -> int:
        """Calculate offset from page number (1-indexed to 0-indexed)."""
        return (page - 1) * limit

    @staticmethod
    def create_metadata(page: int, limit: int, total: int) -> dict:
        """Create pagination metadata for response."""
        return {
            'page': page,
            'limit': limit,
            'total': total,
            'has_more': page * limit < total,
        }

    @staticmethod
    def parse_sort_param(
        sort: str | None,
        allowed_fields: list[str]
    ) -> tuple[str, str] | None:
        """Parse sort parameter to (field, direction) tuple.
        
        Args:
            sort: Sort string format: 'asc_fieldName' or 'desc_fieldName'
            allowed_fields: Whitelist of allowed field names
            
        Returns:
            Tuple of (field, direction) or None if invalid
        """
        if not sort:
            return None

        parts = sort.split('_', 1)
        if len(parts) != 2:
            return None

        direction, field = parts
        if field not in allowed_fields or direction not in ['asc', 'desc']:
            return None

        return (field, direction)
```

**4. API Endpoint with Pagination**

```python
# src/api/projects/routes.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from database.session import get_db
from core.pagination.pagination_service import PaginationService
from core.types.pagination import PaginatedData, PaginatedResponse, PaginationMetadata
from core.validation.schemas import PaginationParams
from models.project import Project as ProjectModel
from .schemas import ProjectResponse

router = APIRouter(prefix='/projects', tags=['projects'])

ALLOWED_SORT_FIELDS = ['name', 'created_at', 'updated_at']

@router.get('', response_model=PaginatedResponse[ProjectResponse])
async def list_projects(
    params: PaginationParams = Depends(),
    session: AsyncSession = Depends(get_db),  # Replace with Session if using sync SQLAlchemy (scaffold default)
) -> PaginatedResponse[ProjectResponse]:
    """List projects with pagination.
    
    Query parameters are validated by PaginationParams via Depends().
    Returns paginated response with metadata.
    """
    # Validate sort field against whitelist
    sort_result = PaginationService.parse_sort_param(params.sort, ALLOWED_SORT_FIELDS)
    if params.sort and not sort_result:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "Invalid sort parameter", "field": "sort"}
        )

    # Calculate offset
    offset = PaginationService.calculate_offset(params.page, params.limit)

    # Query projects
    stmt = select(ProjectModel).offset(offset).limit(params.limit)
    if sort_result:
        field_name, direction = sort_result
        order_col = getattr(ProjectModel, field_name)
        stmt = stmt.order_by(order_col.asc() if direction == 'asc' else order_col.desc())
    else:
        stmt = stmt.order_by(ProjectModel.created_at.desc())

    result = await session.execute(stmt)  # Replace with session.execute(stmt) (no await) for sync SQLAlchemy
    projects = result.scalars().all()

    # Get total count (indexed query)
    count_stmt = select(func.count(ProjectModel.id))
    count_result = await session.execute(count_stmt)  # Replace with session.execute(count_stmt) (no await) for sync SQLAlchemy
    total = count_result.scalar() or 0

    pagination_metadata = PaginationService.create_metadata(params.page, params.limit, total)
    return PaginatedResponse(
        data=PaginatedData(
            items=[ProjectResponse.model_validate(p) for p in projects],
            pagination=PaginationMetadata(**pagination_metadata),
        )
    )
```

## Testing / Verification

```bash
# Test pagination endpoint
curl 'http://localhost:8000/projects?page=1&limit=10'

# Expected 200 response with pagination metadata

# Test invalid page
curl 'http://localhost:8000/projects?page=0&limit=10'
# Expected 422 response

# Test invalid sort
curl 'http://localhost:8000/projects?page=1&limit=10&sort=invalid_field'
# Expected 400 response

pytest -v
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
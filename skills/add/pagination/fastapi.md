<!-- ref: add/pagination/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### FastAPI (Python + Pydantic + SQLAlchemy)

### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

> **Prerequisites**
> This skill assumes the FastAPI scaffold from `templatecentral:scaffold`. File paths below use
> `src/core/` and `src/api/` matching that scaffold layout.
> **If you're using async SQLAlchemy** (`AsyncSession`), ensure `create_async_engine`
> is configured in your project — the default scaffold uses sync SQLAlchemy.
> For sync SQLAlchemy, replace `AsyncSession` with `Session` and remove `await` from
> database calls.

**1. Reusable Pagination Schema**

```python
# src/core/validation/schemas.py
from pydantic import BaseModel, Field

class PaginationParams(BaseModel):
    page: int = Field(default=1, ge=1, le=10_000, description='Page number (1-indexed)')
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

Sync SQLAlchemy (scaffold default):

```python
# src/api/projects/routes.py
from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from sqlalchemy.orm import Session

from core.exceptions import InvalidInputError
from database.session import get_db
from core.pagination.pagination_service import PaginationService
from core.types.pagination import PaginatedData, PaginatedResponse, PaginationMetadata
from core.validation.schemas import PaginationParams
from models.project import Project as ProjectModel
from .schemas import ProjectResponse

router = APIRouter(prefix='/projects', tags=['projects'])

ALLOWED_SORT_FIELDS = ['name', 'created_at', 'updated_at']

@router.get('', response_model=PaginatedResponse[ProjectResponse])
def list_projects(
    params: PaginationParams = Depends(),
    session: Session = Depends(get_db),
) -> PaginatedResponse[ProjectResponse]:
    sort_result = PaginationService.parse_sort_param(params.sort, ALLOWED_SORT_FIELDS)
    if params.sort and not sort_result:
        raise InvalidInputError("Invalid sort parameter")

    offset = PaginationService.calculate_offset(params.page, params.limit)

    stmt = select(ProjectModel).offset(offset).limit(params.limit)
    if sort_result:
        field_name, direction = sort_result
        order_col = getattr(ProjectModel, field_name)
        stmt = stmt.order_by(order_col.asc() if direction == 'asc' else order_col.desc())
    else:
        stmt = stmt.order_by(ProjectModel.created_at.desc())

    projects = session.execute(stmt).scalars().all()

    count_stmt = select(func.count(ProjectModel.id))
    total = session.execute(count_stmt).scalar() or 0

    pagination_metadata = PaginationService.create_metadata(params.page, params.limit, total)
    return PaginatedResponse(
        data=PaginatedData(
            items=[ProjectResponse.model_validate(p) for p in projects],
            pagination=PaginationMetadata(**pagination_metadata),
        )
    )
```

> **Async variant**: If you configured `create_async_engine` and `AsyncSession`, replace `from sqlalchemy.orm import Session` with `from sqlalchemy.ext.asyncio import AsyncSession`, change `Session` → `AsyncSession` in the dependency type, make the handler `async def`, and add `await` before each `session.execute(...)` call.

## Validate

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
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards
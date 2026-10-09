<!-- ref: add/pagination/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### FastAPI (Pydantic + SQLAlchemy)

### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

> **Prerequisites**: FastAPI scaffold + `templatecentral:add (database)` with SQLAlchemy (sync `Session` from `src/database/session.py`). For `AsyncSession`, make the service and handler `async def` and `await` each `session.execute(...)`.

**1. Request Schema**

```python
# src/api/schemas/request/pagination.py
from pydantic import Field

from api.schemas.base import BaseRequestSchema


class PaginationParams(BaseRequestSchema):
    """Shared query params for every paginated list endpoint."""

    # le caps OFFSET cost — an unbounded page is a cheap DoS lever.
    page: int = Field(default=1, ge=1, le=10_000, description="Page number (1-indexed).")
    limit: int = Field(default=10, ge=1, le=100, description="Items per page.")
    sort: str | None = Field(
        default=None,
        max_length=64,
        pattern=r"^(asc|desc)_\w+$",
        description="asc_<field> or desc_<field>.",
    )
```

**2. Response Schema**

```python
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
```

`BaseResponseSchema` serializes `has_more` as `hasMore`, matching the other stacks' envelope.

**3. Pagination Helpers**

```python
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
```

**4. Service + Router**

Query building and sort validation are business logic — they live in the service; the router only binds params and delegates.

```python
# src/api/services/projects.py
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from api.schemas.request.pagination import PaginationParams
from api.schemas.response.pagination import PaginatedData, PaginatedResponse
from api.schemas.response.project import ProjectResponse
from core.exceptions import InvalidInputError
from models.project import Project
from utils.pagination import calculate_offset, create_metadata, parse_sort_param

# API-facing (camelCase) name -> column. The allow-list IS this mapping, so it cannot drift.
SORT_COLUMNS = {
    "name": Project.name,
    "createdAt": Project.created_at,
    "updatedAt": Project.updated_at,
}


def list_projects(session: Session, params: PaginationParams) -> PaginatedResponse[ProjectResponse]:
    sort = parse_sort_param(params.sort, set(SORT_COLUMNS))
    if params.sort and not sort:
        raise InvalidInputError(f"Invalid sort field. Allowed: {', '.join(SORT_COLUMNS)}")

    if sort:
        column = SORT_COLUMNS[sort[0]]
        order_by = column.asc() if sort[1] == "asc" else column.desc()
    else:
        order_by = Project.created_at.desc()

    stmt = (
        select(Project)
        .order_by(order_by)
        .offset(calculate_offset(params.page, params.limit))
        .limit(params.limit)
    )
    rows = session.execute(stmt).scalars().all()
    total = session.execute(select(func.count(Project.id))).scalar_one()

    return PaginatedResponse(
        data=PaginatedData(
            items=[ProjectResponse.model_validate(row) for row in rows],
            pagination=create_metadata(params.page, params.limit, total),
        )
    )
```

```python
# src/api/routers/projects.py
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from api.schemas.request.pagination import PaginationParams
from api.schemas.response.pagination import PaginatedResponse
from api.schemas.response.project import ProjectResponse
from api.services.projects import list_projects
from database.session import get_db

router = APIRouter(prefix="/projects")


@router.get("", response_model=PaginatedResponse[ProjectResponse])
def get_projects(
    # Query() (not Depends()) is what makes extra="forbid" reject unknown query params.
    params: Annotated[PaginationParams, Query()],
    session: Annotated[Session, Depends(get_db)],
) -> PaginatedResponse[ProjectResponse]:
    """List projects, paginated and optionally sorted."""
    return list_projects(session, params)
```

Register with an `APITags` tag in `src/api/routes.py` (see `add/endpoint/fastapi.md`).

## Validate

```bash
# Expect 200 with data.pagination
curl 'http://localhost:8000/projects?page=1&limit=10'
# Expect 422
curl 'http://localhost:8000/projects?page=0&limit=10'
# Expect 400
curl 'http://localhost:8000/projects?sort=asc_bogus'
python -m pytest test/ -v
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
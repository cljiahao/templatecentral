<!-- ref: add/pagination/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### FastAPI (Pydantic + SQLAlchemy)

### Step 0 — Verify context

Need `<!-- templateCentral: fastapi@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

> **Prerequisites**: FastAPI scaffold + `templatecentral:add (database)` with SQLAlchemy (sync `Session` from `src/database/session.py`). For `AsyncSession`, make the service and handler `async def` and `await` each `session.execute(...)`.

Run `TC_PART=leaf TC_LEAF=add/pagination/fastapi bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/pagination/fastapi/template/` (listed in `<skill-dir>/pagination/fastapi/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**1. Request Schema**

Copied verbatim from `<skill-dir>/pagination/fastapi/template/src/api/schemas/request/pagination.py` by the copy step; do not re-type it.

**2. Response Schema**

Copied verbatim from `<skill-dir>/pagination/fastapi/template/src/api/schemas/response/pagination.py` by the copy step; do not re-type it.

`BaseResponseSchema` serializes `has_more` as `hasMore`, matching the other stacks' envelope.

**3. Pagination Helpers**

Copied verbatim from `<skill-dir>/pagination/fastapi/template/src/utils/pagination.py` by the copy step; do not re-type it.

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


def list_projects(
    session: Session, params: PaginationParams
) -> PaginatedResponse[ProjectResponse]:
    sort = parse_sort_param(params.sort, set(SORT_COLUMNS))
    if params.sort and not sort:
        raise InvalidInputError(
            f"Invalid sort field. Allowed: {', '.join(SORT_COLUMNS)}"
        )

    if sort:
        column = SORT_COLUMNS[sort[0]]
        order_by = column.asc() if sort[1] == "asc" else column.desc()
    else:
        order_by = Project.created_at.desc()

    stmt = (
        select(Project)
        # id breaks ties so rows with equal sort keys never repeat or vanish across pages.
        .order_by(order_by, Project.id)
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

If `src/api/routers/projects.py` exists, add this handler and its imports to it — do not replace the file. Register with an `APITags` tag in `src/api/routes.py` and, when `src/api/dependencies/auth.py` exists, add the auth dependency (see `add/endpoint/fastapi.md` Rules).

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

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.
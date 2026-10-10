<!-- ref: add/endpoint/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a FastAPI Endpoint

Guide for adding a new API endpoint following the router → service architecture.

> **Placeholder names**: All examples use a single resource stem, `my_thing` — schema, service, and router files are all `my_thing.py` in their respective directories, with classes `MyThingRequest` / `MyThingResponse`. Replace the stem with your actual resource name throughout (e.g., for a `task` resource: `task.py`, `TaskRequest`, `run_task_service`). The import name must match the filename (e.g., `tasks.py` → `from api.routers import tasks`).

## Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Define Request/Response Schemas

Request schemas inherit `BaseRequestSchema`, responses `BaseResponseSchema` (`src/api/schemas/base.py`: `extra="forbid"`, camelCase aliases, camelCase serialization on responses). Bound every string/list field (`max_length`) — unbounded input is a cheap DoS vector.

**Request** (`src/api/schemas/request/my_thing.py`):
```python
from pydantic import Field

from api.schemas.base import BaseRequestSchema


class MyThingRequest(BaseRequestSchema):
    """Request schema for the new endpoint."""

    field_name: str = Field(
        min_length=1, max_length=200, description="Description of the field."
    )
```

**Response** (`src/api/schemas/response/my_thing.py`):
```python
from pydantic import Field

from api.schemas.base import BaseResponseSchema


class MyThingResponse(BaseResponseSchema):
    """Response schema for the new endpoint."""

    result: str = Field(description="Description of the result.")
```

### 2. Add Service Function

Create `src/api/services/my_thing.py`. Simple endpoints process directly:

```python
from api.schemas.request.my_thing import MyThingRequest
from api.schemas.response.my_thing import MyThingResponse


def run_my_thing_service(request: MyThingRequest) -> MyThingResponse:
    """Orchestrate: parse → process → return."""
    processed = request.field_name.strip().upper()
    return MyThingResponse(result=processed)
```

Non-trivial endpoints convert the schema to a domain model in `src/models/`, process, and serialize back:

```python
from api.schemas.request.my_thing import MyThingRequest
from api.schemas.response.my_thing import MyThingResponse
from models.my_thing import MyThing


def run_my_thing_service(request: MyThingRequest) -> MyThingResponse:
    """Parse schema → process with domain model → serialize result."""
    item = MyThing(field_name=request.field_name)
    result = item.process()
    return MyThingResponse(result=result)
```

### 3. Add Router

Create the endpoint handler in `src/api/routers/my_thing.py`:

```python
from fastapi import APIRouter

from api.schemas.request.my_thing import MyThingRequest
from api.schemas.response.my_thing import MyThingResponse
from api.services.my_thing import run_my_thing_service

router = APIRouter()


@router.post(
    "/my-thing",
    response_model=MyThingResponse,
    status_code=201,
    summary="Short description for OpenAPI docs",
)
async def create_my_thing(body: MyThingRequest) -> MyThingResponse:
    """One-line docstring."""
    return run_my_thing_service(body)
```

### 4. Register the Router

In `src/api/tags.py`, add the new tag:

```python
class APITags(StrEnum):
    # ... existing tags
    MY_TAG = "my-tag"
```

In `src/api/routes.py`, import the router module and register it on the root `router`:

```python
from api.routers import my_thing
from api.tags import APITags

# `router` is the root APIRouter defined at the top of this file
router.include_router(my_thing.router, tags=[APITags.MY_TAG])
```

### 5. Add Tests

Create `test/test_api/test_my_thing.py`:

```python
import pytest
from fastapi.testclient import TestClient


@pytest.mark.unit
def test_create_my_thing_success(client: TestClient) -> None:
    """POST /my-thing returns expected result."""
    response = client.post("/my-thing", json={"fieldName": "value"})
    assert response.status_code == 201
    assert response.json()["result"] == "VALUE"
```

When the route is protected (see Rules), pass the `auth_headers` fixture from `templatecentral:add` (auth) and pin the guard with a 401 test:

```python
@pytest.mark.unit
def test_create_my_thing_success(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    """POST /my-thing returns expected result."""
    response = client.post(
        "/my-thing", json={"fieldName": "value"}, headers=auth_headers
    )
    assert response.status_code == 201


@pytest.mark.unit
def test_create_my_thing_requires_auth(client: TestClient) -> None:
    """POST /my-thing without a token is 401."""
    assert client.post("/my-thing", json={"fieldName": "value"}).status_code == 401
```

### 6. Validate

After creating all files:
1. Start the server (`python src/main.py`) — confirm no import errors
2. Open Swagger docs — verify the new endpoint appears under its tag
3. Run tests from the project root (`python -m pytest test/test_api/test_my_thing.py`) — confirm tests pass
4. Run `ruff check src/` — confirm no lint errors

## Rules

- **Tests are mandatory** — never add or change an endpoint, service, or router without new or updated pytest coverage under `test/` in the same change.
- **Services contain business logic** — parse schemas → process → serialize response.
- **One service function per endpoint**.
- **Apply auth by default when the project has it** — if `src/api/dependencies/auth.py` exists, add the project's auth dependency (`user_id: Annotated[str, Depends(get_current_user)]` — Ruff `FAST002` rejects the bare `= Depends(...)` default) to new endpoints unless the route is deliberately public. Use `status_code=201` on create endpoints.
- NEVER use raw `dict` or unvalidated data in services — always use Pydantic schemas or domain models
- NEVER forget to register the router in `src/api/routes.py` and add the tag to `src/api/tags.py`

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate the server starts and tests pass
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
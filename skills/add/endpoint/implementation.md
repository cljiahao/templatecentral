<!-- ref: add/endpoint/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack = FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a FastAPI Endpoint

Guide for adding a new API endpoint following the router → service architecture.

> **Placeholder names**: All examples use `my_endpoint`, `MyRequest`, `my_service`, etc. Replace these with your actual resource name throughout (e.g., for a `tasks` resource: `tasks.py`, `TaskRequest`, `run_task_service`). The import name must match the filename (e.g., `tasks.py` → `from api.routers import tasks`).

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

Create Pydantic schemas in `src/api/schemas/`. Request schemas inherit from `BaseRequestSchema` and response schemas from `BaseResponseSchema` (both defined in `src/api/schemas/base.py`). They share common config from `BaseSchema` — see the file for the full `ConfigDict`. Key behaviors: `extra="forbid"` rejects unknown fields, `alias_generator=to_camel` converts snake_case to camelCase, and `from_attributes=True` enables ORM-style attribute access. `BaseResponseSchema` additionally sets `serialize_by_alias=True` so responses serialize using camelCase.

**Request** (`src/api/schemas/request/<name>.py`):
```python
from pydantic import Field

from api.schemas.base import BaseRequestSchema


class MyRequest(BaseRequestSchema):
    """Request schema for the new endpoint."""

    field_name: str = Field(description="Description of the field.")
```

**Response** (`src/api/schemas/response/<name>.py`):
```python
from pydantic import Field

from api.schemas.base import BaseResponseSchema


class MyResponse(BaseResponseSchema):
    """Response schema for the new endpoint."""

    result: str = Field(description="Description of the result.")
```

### 2. Add Service Function

Create the service function in `src/api/services/<name>.py`. Services contain the business logic — they parse schemas, process data, and serialize results back.

For simple endpoints, the service can process directly:

```python
from api.schemas.request.my_request import MyRequest
from api.schemas.response.my_response import MyResponse


def run_my_service(request: MyRequest) -> MyResponse:
    """Orchestrate: parse → process → return."""
    processed = request.field_name.strip().upper()
    return MyResponse(result=processed)
```

For non-trivial endpoints with business logic, the service converts Pydantic schemas to domain models, processes, and serializes back. Create domain models in `models/` as needed:

```python
from api.schemas.request.my_request import MyRequest
from api.schemas.response.my_response import MyResponse
from models.my_model import MyItem


def run_my_service(request: MyRequest) -> MyResponse:
    """Parse schema → process with domain model → serialize result."""
    item = MyItem(field_name=request.field_name)
    result = item.process()
    return MyResponse(result=result)
```

> Create `src/models/my_model.py` for domain models — `src/models/base.py` exists as the base. For complex processing, keep pure functions in the model or a utility module under `src/utils/`.

### 3. Add Router

Create the endpoint handler in `src/api/routers/<name>.py`:

```python
from fastapi import APIRouter

from api.schemas.request.my_request import MyRequest
from api.schemas.response.my_response import MyResponse
from api.services.my_service import run_my_service

router = APIRouter()


@router.post(
    "/my-endpoint",
    response_model=MyResponse,
    summary="Short description for OpenAPI docs",
)
def my_endpoint(body: MyRequest) -> MyResponse:
    """One-line docstring."""
    return run_my_service(body)
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
from api.routers import my_endpoint
from api.tags import APITags

# `router` is the root APIRouter defined at the top of this file
router.include_router(my_endpoint.router, tags=[APITags.MY_TAG])
```

Note: `my_endpoint.router` refers to the `router = APIRouter()` instance inside `src/api/routers/my_endpoint.py`. The import name matches the filename (e.g., `example.py` → `from api.routers import example`).

### 5. Add Tests

Create `test/test_api/test_my_endpoint.py`:

```python
import pytest
from fastapi.testclient import TestClient


@pytest.mark.unit
def test_my_endpoint_success(client: TestClient) -> None:
    """POST /my-endpoint returns expected result."""
    response = client.post("/my-endpoint", json={"fieldName": "value"})
    assert response.status_code == 200
    assert response.json()["result"] == "VALUE"
```

### 6. Validate

After creating all files:
1. Start the server (`python src/main.py`) — confirm no import errors
2. Open Swagger docs — verify the new endpoint appears under its tag
3. Run tests from the project root (`pytest test/test_api/test_my_endpoint.py`) — confirm tests pass
4. Run `ruff check src/` — confirm no lint errors

## Rules

- **Tests are mandatory** — never add or change an endpoint, service, or router without new or updated pytest coverage under `test/` in the same change.
- **Services contain business logic** — parse schemas → process → serialize response.
- **One service function per endpoint**.
- NEVER use raw `dict` or unvalidated data in services — always use Pydantic schemas or domain models
- NEVER forget to register the router in `src/api/routes.py` and add the tag to `src/api/tags.py`

## Validate

```bash
pytest test/ -v     # tests pass
ruff check src/     # zero lint errors
```

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate the server starts and tests pass
2. `templatecentral:review` — check code standards
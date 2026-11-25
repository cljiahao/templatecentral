<!-- ref: add/test/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI

**Policy**: Same-change pytest for new/changed API code (root `AGENTS.md`, `code-standards/`). Apply the test-value rule (`docs/CONSTITUTION.md` §4).

### Steps

**Context check:** Confirm `src/api/routers/` contains at least one `.py` file. If not, stop and tell the user: "No routers found. Run
`templatecentral:add` (endpoint) first, then return here."

### Test Structure

Tests mirror `src/`:

```
test/
├── conftest.py           # Shared fixtures (TestClient) — created by scaffold
├── factories/            # Factory functions for test data
│   └── models.py
└── test_api/             # API endpoint tests
    └── test_<endpoint>.py
```

Add directories as needed: `test_services/` (business logic), `test_models/` (domain models), `test_utils/` (utilities).

### Fixtures

The scaffold generates `test/conftest.py` with a `client` fixture:

```python
"""Root conftest — shared fixtures available to all tests."""

from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from app import app


@pytest.fixture
def client() -> Generator[TestClient]:
    """FastAPI test client."""
    with TestClient(app) as client:
        yield client
```

After `templatecentral:add` (auth) or (database), the conftest seeds placeholder settings with `os.environ.setdefault(...)` and imports `app` inside the fixture — keep that shape: anything importing `core.config` at module top runs before the seeding and fails in CI, where there is no `src/.env`.

Extend it for database tests by overriding dependencies:

```python
# test/conftest.py — merge these imports into the existing import block
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool


@pytest.fixture
def db_client() -> Generator[TestClient]:
    """TestClient with a clean in-memory database for each test."""
    # Imported after the env seeding; importing app also registers every model on Base.metadata.
    from app import app
    from database.base import Base
    from database.session import get_db

    # StaticPool + check_same_thread=False keep the in-memory SQLite database visible to TestClient's thread.
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    TestSession = sessionmaker(bind=engine)
    session = TestSession()
    app.dependency_overrides[get_db] = lambda: session

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()
    session.close()
    engine.dispose()
```

### Naming

- Functions: `test_<subject>_<scenario>`. No docstring or marker needed when the name says it; add a marker only to select a subset. `unit` and `integration` are registered in `pyproject.toml`; register any other in `markers` first.

### Factories

Create factory functions in `test/factories/` with sensible defaults:

```python
def create_example_request(
    name: str = "World",
    repeat_count: int = 1,
) -> dict:
    """Create an example request payload with camelCase keys matching the API contract."""
    return {"name": name, "repeatCount": repeat_count}
```

> **camelCase keys**: `BaseSchema` uses `alias_generator=to_camel`, so factory return values use camelCase keys (`"repeatCount"`) though Python params are snake_case.

### Parametrize

Default for tests that differ only by input/output (never copy-paste siblings) — `@pytest.mark.parametrize` with `ids=`.

### Running Tests

```bash
python -m pytest test/                    # All tests
python -m pytest test/test_api/           # API tests only
```

### Rules

- Assert errors with `pytest.raises(..., match=...)`; prefer `monkeypatch` over `unittest.mock.patch`; mock only network, filesystem and time

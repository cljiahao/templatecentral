---
paths:
  - "skills/**"
---

# FastAPI Rules

Stack: FastAPI 0.136+, Python 3.13, Pydantic ≥2.9.0 (camelCase schemas), Starlette ≥1.0.1 (BadHost auth-bypass advisory fix; current stable 1.3.1), Uvicorn, Ruff, pytest, Docker. Logging: python-json-logger ≥4.0. MongoDB: pymongo ≥4.13 (AsyncMongoClient GA floor), beanie ≥2.0 (built on PyMongo async — Motor is deprecated, never add it).

## Boundaries

- NEVER violate dependency flow: `api/` (routers → services) → `models/` (never reversed)
- NEVER pass Pydantic schemas into domain models directly — convert in the service layer
- NEVER use `Optional[X]` or `List[X]` — use `X | None` and `list[X]`
- NEVER skip `response_model` on route decorators

## Architecture

- Layered: `api/` (routers, schemas, services) → `models/` (domain models — dataclasses, or ORM/ODM models after `add-database`)
- Shared: `core/` (config, logging, exceptions), `utils/`
- Tests: `test/conftest.py`, `test/factories/`, `test/test_api/`

## Standards

- **Backend tests**: same-change pytest for API code (`test/`) — root `AGENTS.md`, `templatecentral:standards`.
- Naming, types, imports, schemas: `templatecentral:standards`.

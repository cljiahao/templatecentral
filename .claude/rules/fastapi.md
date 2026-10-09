---
paths:
  - "skills/**"
---

# FastAPI Rules

Stack: FastAPI 0.136+ (current stable 0.143.x), Python 3.14 (Docker `python:3.14.x-slim`, ruff `py314`, pyright `3.14`, CI setup-python `3.14`; 3.13 is security-fixes-only since 2026-10-01), Pydantic ≥2.12 (first release supporting Python 3.14/PEP 649 deferred annotations; camelCase schemas; current stable 2.14.x), Starlette ≥1.3.1 (High form-limit DoS advisory GHSA-82w8-qh3p-5jfq; also covers the 1.0.1 BadHost and 1.1.0/1.3.0 fixes; current stable 1.7.x), python-multipart ≥0.0.31 (querystring DoS/smuggling advisories), Uvicorn, Ruff, pytest, Docker. Logging: structlog ≥25.1 (JSON in prod/uat, console in dev; kwargs not `extra=`). Request-ID correlation (via `templatecentral:add (logging)`): asgi-correlation-id ≥4.3. MongoDB: pymongo ≥4.13 (AsyncMongoClient GA floor), beanie ≥2.0 (built on PyMongo async — Motor is deprecated, never add it; every release since 2.0.1 caps `Requires-Python <3.14` (PEP 649 breaks `Link` forward refs), so pip silently resolves 2.0.0 on 3.14 — the beanie guide's B0 check decides between pinning Python 3.13 or using PyMongo's `AsyncMongoClient` directly).

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

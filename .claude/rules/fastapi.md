---
paths:
  - "skills/**"
---

# FastAPI Rules

Stack: FastAPI 0.136+ (current stable 0.143.x), Python 3.14 (Docker `python:3.14.x-slim`, ruff `py314`, pyright `3.14`, CI setup-python `3.14`; 3.13 is security-fixes-only since 2026-10-01), Pydantic ≥2.12 (first release supporting Python 3.14/PEP 649 deferred annotations; camelCase schemas; current stable 2.14.x), Starlette ≥1.3.1 (High form-limit DoS advisory GHSA-82w8-qh3p-5jfq; also covers the 1.0.1 BadHost and 1.1.0/1.3.0 fixes; current stable 1.7.x), python-multipart ≥0.0.31 (querystring DoS/smuggling advisories), Uvicorn, Ruff, pytest, Docker. Logging: structlog ≥25.1 (JSON in prod/uat, console in dev; kwargs not `extra=`). Request-ID correlation (via `templatecentral:add (logging)`): asgi-correlation-id ≥4.3. MongoDB: PyMongo async is the default — pymongo ≥4.13 (`AsyncMongoClient` GA floor; current 4.18.x, official 3.14 support) with Pydantic models + repositories (`add/database/python/pymongo-async.md`). Motor is deprecated (never add it); ODMantic needs Motor (not viable). Beanie is explicit opt-in only and pins the project to Python 3.13: floor `beanie>=2.2,<3` because 2.0.1–2.2.0 declare `Requires-Python <3.14` (maintainer decision pending v3 — BeanieODM/beanie#1257/#1362/#1373; never `--ignore-requires-python`), and a bare `beanie>=2.0` silently resolves 2.0.0 on 3.14. Never `from __future__ import annotations` in Beanie model modules (breaks `Link`/`BackLink` detection).

## Boundaries

- NEVER violate dependency flow: `api/` (routers → services) → `models/` (never reversed)
- NEVER pass Pydantic schemas into domain models directly — convert in the service layer
- NEVER use `Optional[X]` or `List[X]` — use `X | None` and `list[X]`
- NEVER skip `response_model` on route decorators
- Browser SPA clients authenticate via the auth skill's cookie mode (HttpOnly `__Host-session` + session-bound `XSRF-TOKEN`/`X-CSRF-Token`, `POST /auth/session`/`/auth/logout`) — keep Vite's auth service, `add/auth/fastapi.md`, and `standards/full-stack-pairing` aligned on these names

## Architecture

- Layered: `api/` (routers, schemas, services) → `models/` (domain models — dataclasses, or ORM/ODM models after `add-database`)
- Shared: `core/` (config, logging, exceptions), `utils/`
- Tests: `test/conftest.py`, `test/factories/`, `test/test_api/`

## Standards

- **Backend tests**: same-change pytest for API code (`test/`) — root `AGENTS.md`, `templatecentral:standards`.
- Naming, types, imports, schemas: `templatecentral:standards`.

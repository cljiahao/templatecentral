---
paths:
  - "templates/fastapi/**"
  - "claude-skills/fastapi/**"
---

# FastAPI Rules

Stack: FastAPI 0.116, Python 3.12, Pydantic v2 (camelCase schemas), Uvicorn, Ruff, pytest, Docker.

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

- **Backend tests**: same-change pytest for API code (`test/`) — root `AGENTS.md`, `claude-skills/fastapi/code-standards/SKILL.md`.
- Naming, types, imports, schemas: `code-standards/SKILL.md`.

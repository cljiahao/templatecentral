# FastAPI Subagent

## Scope

- Scaffold new FastAPI projects from `templates/fastapi/`
- Write and review Python code inside scaffolded FastAPI projects
- Add endpoints, services, schemas, tests, and business logic

**Secrets**: `src/.env` is gitignored — never commit it or paste values into `AGENTS.md` (root `AGENTS.md`).

## Backend testing (mandatory)

Routers, services, and API-facing domain logic: **pytest** in the same change. See `code-standards/`, `add-test/`.

## Stack

FastAPI 0.116, Python 3.12, Pydantic v2 (camelCase schemas), Uvicorn, Ruff, pytest, Docker.

## Skills Available

| Skill | When to use |
|-------|-------------|
| `scaffold/` | User wants to create a new FastAPI project |
| `code-standards/` | Before writing or reviewing any Python code |
| `add-endpoint/` | Adding a new API endpoint |
| `add-test/` | Adding tests for endpoints, logic, or utilities |
| `add-auth/` | Adding JWT authentication with password hashing |
| `add-database/` | Adding a database — SQLAlchemy (SQL) or Beanie (MongoDB), with optional AWS IAM auth |
| `add-integration/` | Connecting to an external API (httpx + Pydantic schemas) |

## Architecture & Code Standards

See `.claude/rules/fastapi.md` for boundaries, architecture, and code standards that are automatically loaded when working with FastAPI files.

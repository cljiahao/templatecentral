<!-- templateCentral: fastapi@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

## Stack
FastAPI 0.136+ · Python 3.14 · Pydantic v2 · Uvicorn · Ruff · pytest · pyright

## Commands
```bash
python src/main.py            # dev server (http://localhost:8000)
python -m pytest test/ -v     # run tests (from project root)
ruff check src/               # lint
ruff format src/              # format
python -m pyright src/        # type check
```

## Architecture
- Layered flow: `api/` (routers → services) → `models/` (never reversed)
- Pydantic schemas with camelCase aliases (`BaseSchema`)
- Centralized exception → HTTP response mapping in `error_handler.py`
- Routers are thin — accept body, call service, return result

## Skills
### Project skills — check here first
| Skill | What it does |
|-------|-------------|
| `/api-verify` | pyright + ruff + tests in one pass |

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect SQLAlchemy/MongoDB |
| `templatecentral:add (endpoint)` | new route + schema + service method |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |

## Rules (always)
- Type annotations on all public function parameters and return types
- All user input validated with Pydantic at every boundary; use `response_model` to strip internal fields
- snake_case files/functions/variables; PascalCase classes; UPPER_SNAKE_CASE constants
- No secrets in code — use env vars; document in `.env.example`
- Comments: default none; names carry meaning. When needed, one short line above the code stating the non-obvious reason, never trailing or in brackets, never change history; cite an ADR by id only (`// ADR-0049`).
- Docstrings/JSDoc only on public APIs unclear from signature and types: one summary line. No commented-out code.
- Fix the cause; suppress (`eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`) only a confirmed false positive or third-party constraint, one line, one rule, with the reason. No `NOSONAR`, no file-level disables, no coverage/Sonar exclusions.
- Tests: one per distinct behaviour; parametrize sibling cases; extend an existing test before adding one; no tests for constants, types or framework behaviour.
- Quality gate: SonarQube default (cognitive complexity 15, duplication 3% and coverage 80% on new code). Meet it by fixing code, not by excluding or suppressing.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->

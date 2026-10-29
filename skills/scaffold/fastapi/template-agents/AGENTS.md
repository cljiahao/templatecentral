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
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/api-verify` | pyright + ruff + tests in one pass |

Add new project skills here whenever you repeat a workflow more than once.

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
- Comments explain *why*, not *what* — no commented-out code (Ruff `ERA`), no change-narration (`# was X, now Y`); own-line over trailing. See `templatecentral:standards (code-standards)`

(AGENTS.md tail — AI Harness / Skills Security / Git Workflow / Skill capture — is appended by harness-kit-finalize.md Step G; not embedded here to avoid duplication.)

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->

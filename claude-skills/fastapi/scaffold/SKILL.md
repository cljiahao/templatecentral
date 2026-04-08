---
name: scaffold
description: Use when the user wants to start a new Python backend project, create a new FastAPI API, or scaffold a project with layered architecture and Docker support.
---

# Scaffold FastAPI Project

Scaffold a new FastAPI backend project from the templateCentral FastAPI template.

## Inputs

- **Project name** — The name for the new project (e.g., `my-api`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-api`). If not provided, default to `./<project-name>` and confirm with the user.

## Steps

### 1. Copy the Template

Copy the entire `templates/fastapi/` directory from this repository to the target directory. Exclude `__pycache__/` and `log/`.

```bash
rsync -av --exclude='__pycache__' --exclude='log' --exclude='.venv' --exclude='.env' <repo-root>/templates/fastapi/ <target-directory>/
```

### 2. Update Project Settings

In `src/core/config.py`, update the `CommonSettings` defaults:
- `PROJECT_NAME` — Set to the project name
- `PROJECT_DESCRIPTION` — Set to a relevant description
- `PROJECT_VERSION` — Set to `"v0.1.0"` or the user's preferred version

### 3. Create Environment Files

Copy `src/.env.default` to create `src/.env`:

```bash
cp src/.env.default src/.env
```

Update values as needed (project name, port, etc.).

### 4. Set Up Virtual Environment

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
```

**Checkpoint**: Verify all packages installed without errors. Run `pip check` to detect dependency conflicts.

### 5. Verify

```bash
cd src
python main.py
```

Confirm the API starts at `http://localhost:8000` and Swagger docs are available. **Do not proceed until the API responds.**

Run tests (from the project root, not from `src/`):

```bash
cd ..
pytest test/
```

**Checkpoint**: All tests must pass. If any fail, fix before proceeding.

```bash
ruff check src/
```

**Checkpoint**: Ruff must be clean before generating `AGENTS.md`.

### 6. Generate Project AGENTS.md (MANDATORY)

**Required** — root `AGENTS.md` Project Memory; only after verification gates pass.

Create `AGENTS.md` in the project root. This gives any AI agent (Cursor, Codex, Copilot, Windsurf, etc.) permanent context about this specific project.

```markdown
# <Project Name>

## Identity
- **Stack**: FastAPI 0.116, Python 3.12, Pydantic v2, Uvicorn, Ruff, pytest
- **Scaffolded from**: templateCentral/templates/fastapi
- **Created**: <date>

## Architecture Decisions
- Layered dependency flow: `api/` (routers → services) → `models/`
- Pydantic schemas with camelCase aliases (`BaseSchema`)
- Structured JSON logging with timed rotating file handler
- Centralized exception → HTTP response mapping in `error_handler.py`

## Key Conventions
- snake_case for files/functions/variables; PascalCase for classes; UPPER_SNAKE_CASE for constants
- Type annotations on all public function parameters and return types
- Routers are thin — accept body, call service, return result
- Services orchestrate — parse → process → return
- Absolute imports only; no wildcards; stdlib → third-party → local
- **Testing**: New or changed API/services/domain logic must include pytest coverage in the same change (`pytest` from project root)

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Update the Identity section with the actual project name and creation date.

### 7. Generate Project CLAUDE.md (MANDATORY for Claude Code users)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Follow **Scaffold: CLAUDE.md (Claude Code only)** in repository root `AGENTS.md`. Write a **short** `CLAUDE.md` (do not duplicate `AGENTS.md` architecture/conventions — point to `AGENTS.md`).

Include **Build & Dev** with verified commands only, e.g.:

- `source .venv/bin/activate` — venv
- `cd src && python main.py` — dev server (http://localhost:8000)
- `pytest test/` — tests (project root)
- `ruff check src/` — lint

**templateCentral skills** (this stack): `scaffold` (done), `add-endpoint`, `add-auth`, `add-database`, `add-integration`, `add-test`. **Workflow**: simple/medium → `claude-skills/fastapi/`; complex → Superpowers (see root `AGENTS.md`). **Never** put secrets in `CLAUDE.md`.

### 8. Task Management (Optional)

Ask whether the user wants structured task management for complex features. If **yes**, append **Option A** or **Option B** from **Scaffold: optional Task Management** in repository root `AGENTS.md` (templateCentral). If **no**, skip.

### 9. Remove Example Code (Optional)

Once the project is verified, remove the example endpoint:
- Delete `src/api/routers/example.py`
- Delete `src/api/schemas/request/example.py`
- Delete `src/api/schemas/response/example.py`
- Delete `src/api/services/example.py`
- Delete `test/test_api/test_example.py`
- Remove the `example` import and `include_router` line from `src/api/routes.py`
- Update `APITags` in `src/api/tags.py` to remove `EXAMPLE`

## Rules

- Always create a virtual environment before installing dependencies; NEVER install packages globally
- Always copy `src/.env.default` to `src/.env` before first run — **never** commit `src/.env` or put secrets in generated `AGENTS.md` / `CLAUDE.md`
- Verify the API starts and Swagger docs render before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `__pycache__/`, `log/`, `src/.env`, or `.venv/` when scaffolding
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove `conftest.py` or `factories/` when cleaning up example code — they're shared test infrastructure

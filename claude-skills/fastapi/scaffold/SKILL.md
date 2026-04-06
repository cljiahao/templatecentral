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
rsync -av --exclude='__pycache__' --exclude='log' <repo-root>/templates/fastapi/ <target-directory>/
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

### 6. Generate Project AGENTS.md (MANDATORY)

**This step is NOT optional. Do NOT skip it. Scaffolding is incomplete without a project AGENTS.md.**

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

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Update the Identity section with the actual project name and creation date.

### 7. Generate Project CLAUDE.md (MANDATORY for Claude Code users)

**This step is NOT optional when the user uses Claude Code.** If the user uses only Cursor/Copilot/Windsurf (no Claude Code), skip this step — `AGENTS.md` is sufficient.

Create `CLAUDE.md` in the project root. Claude Code reads this file automatically at session start and uses it as persistent project context.

```markdown
# <Project Name>

FastAPI backend scaffolded from templateCentral.

## Build & Dev

- `source .venv/bin/activate` — activate virtual environment
- `cd src && python main.py` — start dev server (http://localhost:8000)
- `pytest test/` — run test suite (from project root)
- `ruff check src/` — lint

## Architecture

- Layered dependency flow: `api/` (routers → services) → `models/`
- Pydantic v2 schemas with camelCase aliases (`BaseSchema`)
- Structured JSON logging with timed rotating file handler
- Centralized exception → HTTP response mapping in `error_handler.py`
- Settings via Pydantic Settings with `src/.env` support

## Conventions

- snake_case for files/functions/variables; PascalCase for classes; UPPER_SNAKE_CASE for constants
- Type annotations on all public function parameters and return types
- Routers are thin — accept body, call service, return result
- Absolute imports only; no wildcards; stdlib → third-party → local

## Workflow

Use this decision tree for all tasks:

| Task complexity | Approach |
|----------------|----------|
| Simple (add endpoint, add schema, single-file change) | Follow templateCentral skills directly — see `claude-skills/fastapi/` in templateCentral repo |
| Medium (add feature module, add integration, add database) | Follow templateCentral skills — they have complete step-by-step instructions |
| Complex (3+ files, architectural decisions, multi-step feature) | Use Superpowers plugin workflow: `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan` |
| Debugging | Use Superpowers `systematic-debugging` skill if installed, otherwise debug normally |

**Important**: Regardless of which workflow is used, ALL code must follow the conventions above and the patterns in `AGENTS.md`.

## templateCentral Reference

This project was scaffolded from `templateCentral/templates/fastapi`. Available skills for this stack:

- `scaffold` — initial project setup (already done)
- `add-endpoint` — add a new API endpoint
- `add-auth` — add authentication
- `add-database` — add SQLAlchemy (SQL) or Beanie (MongoDB)
- `add-integration` — add external API integration
- `add-test` — add tests for existing code
```

Update the project name and customize the skills list if any don't apply.

### 8. Task Management (Optional)

Ask the user: *"Do you want structured task management for complex features? You have two options:"*

**Option A — templateCentral built-in** (no plugin required):

Append to the project's `AGENTS.md`:

```markdown
## Task Management

For complex, multi-step tasks (3+ files, architectural decisions), follow the task management protocol at `claude-skills/shared/task-management/SKILL.md` in templateCentral.

Protocol summary: Plan → Verify → Track → Explain → Document → Capture Lessons.

Skip for simple changes (single-file edits, scaffolding, quick fixes).
```

**Option B — Superpowers plugin** (recommended for Claude Code users building complex features):

Tell the user to install Superpowers in their Claude Code session:

```bash
/plugin marketplace add pcvelz/superpowers
/plugin install superpowers-extended-cc@superpowers-extended-cc-marketplace
```

Then append to the project's `AGENTS.md`:

```markdown
## Task Management

- **Simple tasks** (add endpoint, add schema): use templateCentral skills directly
- **Complex features** (3+ files, architectural decisions): use Superpowers workflow — `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`
- All code must follow the conventions in this file and the project's code-standards, regardless of workflow used
```

If the user doesn't want either, skip this step entirely.

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
- Always copy `src/.env.default` to `src/.env` before first run
- Verify the API starts and Swagger docs render before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `__pycache__/`, `log/`, `src/.env`, or `.venv/` when scaffolding
- NEVER scaffold into a non-empty directory without confirming with the user
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove `conftest.py` or `factories/` when cleaning up example code — they're shared test infrastructure

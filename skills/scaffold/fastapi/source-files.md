<!-- ref: scaffold/fastapi/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Config Files

The config files are real files in `<skill-dir>/fastapi/template/`, listed in `<skill-dir>/fastapi/template.manifest`. Step 1 below copies them; do not re-type them. Notes on the ones that need context:

- `requirements-dev.txt` — Dev-only dependencies, not installed in production Docker stages. `pytest-cov` is required by the seeded CI coverage gate (`pytest --cov=src --cov-report=xml`, harness-kit Step B3) — the FastAPI counterpart to the TS stacks' `@vitest/coverage-v8`.
- `pyrightconfig.json` — Pins pyright to the project venv so `python -m pyright src/` resolves imports from `.venv` even when the venv is not the active shell. Without it, pyright falls back to the system Python and reports every dependency as a missing import.

## Part C — Source Files

The source files are real files in `<skill-dir>/fastapi/template/` (and `AGENTS.md` in `<skill-dir>/fastapi/template-agents/`), listed in `<skill-dir>/fastapi/template.manifest`. Steps 1 and 6 below copy them; do not re-type or modify them. Notes on the ones that need context:

- `src/core/uvicorn_log_config.json` — Passed to the `uvicorn` CLI via `--log-config` in `docker-entrypoint.sh` (the CLI bypasses `main.py`, so `uvicorn.run(..., log_config=None)` there doesn't apply). uvicorn's own default logging config installs handlers directly on the `uvicorn`/`uvicorn.access` loggers with `propagate: false`, which bypasses the root handler `setup_logging()` configures — this file clears those handlers and re-enables propagation so uvicorn's startup/access logs go through the same structlog JSON formatting as app-level `logger.info(...)` calls.

---

## Scaffold Steps

### 1. Create target directory and copy the template files

Create `<target>/`, then load the kit index: its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh` (later steps run it with other `PART` values).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=fastapi TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/fastapi/template/` into the project root per `<skill-dir>/fastapi/template.manifest`, with the kit's path rules and refusals: it writes nothing and ends with a `STOP:` line when a path is in the way.

Then write `README.md`: name, the one-sentence description from Step 2, and a Quickstart with the Step 4 commands and the `## Commands` section of `<skill-dir>/fastapi/template-agents/AGENTS.md`. Kit Step E3 never overwrites this prose; it only appends `## Structure`.

Do NOT create `requirements.txt` yet — it is produced by `pip freeze` in Step 4.

### 2. Update project settings

In `src/core/config.py`, update the `CommonSettings` defaults:
- `PROJECT_NAME` — Set to the project name supplied by the user
- `PROJECT_DESCRIPTION` — Set to a relevant one-sentence description
- `PROJECT_VERSION` — Set to `"v0.1.0"` (or user's preferred version)

### 3. Create environment file

```bash
cp src/.env.default src/.env
```

`CommonSettings`/`APISettings` load `src/.env` directly (`SettingsConfigDict(env_file="src/.env")`), which takes priority over the class defaults edited in Step 2 — update `PROJECT_NAME`/`PROJECT_VERSION`/`PROJECT_DESCRIPTION` in `src/.env` to match Step 2's values now, or Step 2's edits are silently overridden at runtime. Never commit `src/.env`.

### 4. Set up virtual environment and install dependencies

```bash
git init
python3.14 -m venv .venv    # Python 3.14 — matches the Dockerfile image, ruff target-version and pyright pythonVersion
source .venv/bin/activate   # Linux/Mac

# certifi floor: older bundles still trust the compromised eMudhra intermediate CAs (Oct 2026).
pip install "fastapi>=0.136" "uvicorn[standard]" "pydantic>=2.12" pydantic-settings python-dotenv "python-multipart>=0.0.31" "structlog>=25.1" "starlette>=1.3.1" "certifi>=2026.10.19"

# Freeze BEFORE dev deps are installed — requirements.txt is what the Dockerfile's
# prod-deps stage installs, so it must contain runtime packages only.
pip freeze > requirements.txt

pip install -r requirements-dev.txt
```

**Checkpoint**: Run `pip check` to detect dependency conflicts. Fix before proceeding.

### 5. Verification gate (do not proceed until this passes)

```bash
python src/main.py &       # starts server; confirm http://localhost:8000 responds
python -m pytest test/ -v  # all tests must pass
ruff check src/            # zero lint errors
ruff format --check src/   # zero formatting drift
python -m pyright src/     # zero type errors
```

> Run `ruff format src/` once first if this is a fresh scaffold — formatting drift on newly generated files will cause the format check to fail until formatted.

**Do not generate AGENTS.md until all checks pass.**

### 6. Write project AGENTS.md

Run kit Step **0** again as `TC_STACK=fastapi TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies `AGENTS.md` from `<skill-dir>/fastapi/template-agents/` and refuses when the project already holds one. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project name. The title must be a single line: if it contains a newline, stop and ask the user for a one-line title, and edit nothing.

Afterwards, check that no placeholder is left anywhere in the project:

```bash
grep -rn '__TC_' . --exclude-dir=.venv --exclude-dir=.git
```

It must print nothing.

### 6b. Seed the agent harness (shared kit)

Load the rest of the shared harness kit (the index was loaded in Step 1) using the **fastapi** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit-fastapi.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Execute kit Step **0** now as `TC_STACK=fastapi TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"` (harness template trees), then Steps **A through D** (settings.json with `TC_PART=settings`, hook notes, then FUTURE.md, CONSTITUTION.md and `/skill-audit` with `TC_PART=late`, each run of `tc-copy.sh` with `TC_STACK=fastapi`). The verify skill (6c) is already in place, which Step E requires.

### 6c. Project skill files (`.claude/skills/`)

`.claude/skills/api-verify/SKILL.md` was copied in Step 1. A project skill is a **directory** with `SKILL.md` as the entrypoint; flat `.claude/skills/<name>.md` files are silently ignored.

### 6d. Seed additional project skills

Ask whether any repeated workflow should become a project skill. Candidates:
- `api-migrate` — Alembic migration with safety gate (if SQLAlchemy/Alembic is wired up)
- `api-endpoint` — scaffold a new router + schema + service method

If yes, create them in `.claude/skills/` and add a row to the `AGENTS.md` Skills table.

Now execute kit Steps **E through H** using the **fastapi** row: harness.json (Step E — includes the `api-verify` skill hash), the base snapshot (Step E2), per-folder documentation (Step E3), `.agents` symlink (Step F), AGENTS.md tail append (Step G — always appends the shared tail fragment with the fastapi `PostToolUse` line), and plugin install (Step H).

---

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` into every Claude Code session; keep everything else in `AGENTS.md`.

After creating it, add a `CLAUDE.md` entry to `seeded_files` in `.claude/harness.json` with its SHA-256 hash (see harness-kit-finalize.md Step E).

### 8. Task management (optional)

Ask whether the user wants structured task management for complex features. If yes, append the task-management section to the project's `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/fastapi/template-tail/task-management.md" >> AGENTS.md
```

### 9. Remove example code (optional)

Once the project is verified, use the cleanup utility — load it with: `cat "<skill-dir>/../cleanup/SKILL.md"`.

FastAPI-specific steps (the skill covers these):
- Delete `src/api/routers/example.py`, `src/api/schemas/request/example.py`, `src/api/schemas/response/example.py`, `src/api/services/example.py`, `test/test_api/test_example.py`
- Remove `example` import and `include_router` from `src/api/routes.py`
- Remove `EXAMPLE` from `APITags` in `src/api/tags.py`

---

## Rules

- Always create a virtual environment before installing dependencies; NEVER install packages globally
- **Never** commit `src/.env` or put secrets in generated `AGENTS.md` / `CLAUDE.md`
- Verify the API starts and Swagger docs render before handing off; remove example code only after the user confirms the project runs
- NEVER include `__pycache__/`, `log/`, `src/.env`, or `.venv/` when writing project files
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove `conftest.py` or `factories/` when cleaning up example code — they're shared test infrastructure
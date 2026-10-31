<!-- ref: scaffold/fastapi/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes — config files

The config files are real files in `<skill-dir>/fastapi/template/`, listed in `<skill-dir>/fastapi/template.manifest`. Step 1 below copies them; do not re-type them. Notes on the ones that need context:

- `requirements-dev.txt` — Dev-only dependencies, not installed in production Docker stages. `pytest-cov` is required by the seeded CI coverage gate (`pytest --cov=src --cov-report=xml`, harness-kit Step B3) — the FastAPI counterpart to the TS stacks' `@vitest/coverage-v8`.
- `pyrightconfig.json` — Pins pyright to `.venv`, so `python -m pyright src/` resolves imports when the venv is not active.

## Template notes — source files

The source files are real files in `<skill-dir>/fastapi/template/` (and `AGENTS.md` in `<skill-dir>/fastapi/template-agents/`), listed in `<skill-dir>/fastapi/template.manifest`. Steps 1 and 6 below copy them; do not re-type or modify them. Notes on the ones that need context:

- `src/core/uvicorn_log_config.json` — Passed to the `uvicorn` CLI via `--log-config` in `docker-entrypoint.sh`. It clears uvicorn's own handlers and re-enables propagation, so uvicorn's startup/access logs get the same structlog JSON formatting as the app.

---

## Scaffold Steps

### 1. Create target directory and copy the template files

Create `<target>/`, then load the kit index: its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh` (later steps run it with other `PART` values).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=fastapi TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/fastapi/template/` into the project root per `<skill-dir>/fastapi/template.manifest`: it writes nothing and ends with a `STOP:` line when a path is in the way.

Then write `README.md`: name, the one-sentence description from scaffold Step 1, and a Quickstart with the Step 4 commands and the `## Commands` section of `<skill-dir>/fastapi/template-agents/AGENTS.md`. Kit Step E3 never overwrites this prose; it only appends `## Structure`.

Do not create `requirements.txt` yet: Step 4 produces it with `pip freeze`.

### 2. Update project settings

In `src/core/config.py`, update the `CommonSettings` defaults:
- `PROJECT_NAME` — Set to the project name supplied by the user
- `PROJECT_DESCRIPTION` — Set to a relevant one-sentence description
- `PROJECT_VERSION` — Set to `"v0.1.0"` (or user's preferred version)

`CommonSettings` loads `src/.env`, whose values win over these defaults, so set the same `PROJECT_NAME` and `PROJECT_VERSION` in `src/.env.default` too. Step 3 copies that file to `src/.env`; agents do not edit `src/.env` itself.

### 3. Create environment file

```bash
cp src/.env.default src/.env
```

If a guard in your session blocks writing the env file, ask the user to run this copy and continue once it exists.

Never commit `src/.env`.

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
ruff format src/           # format fresh files once, so the format check below passes
python -m uvicorn --app-dir src app:app --port 8000 & server=$!   # no --reload: $server is the server itself
curl -fsS --retry 10 --retry-connrefused --retry-delay 1 http://localhost:8000/health; kill "$server"
python -m pytest test/ -v  # all tests must pass
ruff check src/            # zero lint errors
ruff format --check src/   # zero formatting drift
python -m pyright src/     # zero type errors
```

**Do not generate AGENTS.md until all checks pass.**

### 6. Write project AGENTS.md

Run kit Step **0** again as `TC_STACK=fastapi TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies `AGENTS.md` from `<skill-dir>/fastapi/template-agents/` and refuses when the project already holds one. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project title. The title must be a single line: if it contains a newline, stop and ask the user for a one-line title, and edit nothing.

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

Execute kit Step **0** now as `TC_STACK=fastapi TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"` (harness template trees), then Steps **A through D** (settings.json with `TC_PART=settings`, hook notes, then FUTURE.md, CONSTITUTION.md and `/skill-audit` with `TC_PART=late`, each run of `tc-copy.sh` with `TC_STACK=fastapi`). The verify skill (6c) is already in place, which Step E requires. FastAPI runs `TC_PART=base` here rather than before the install: it has no `prepare` script for lefthook to hook into, so nothing at install time needs `lefthook.yml`. Once Step 0 has copied `lefthook.yml`, run `lefthook install` inside the venv (`requirements-dev.txt` already installed it) so the git hooks are active.

### 6c. Project skill files (`.claude/skills/`)

`.claude/skills/api-verify/SKILL.md` was copied in Step 1. A project skill is a **directory** with `SKILL.md` as the entrypoint; flat `.claude/skills/<name>.md` files are silently ignored.

### 6d. Seed additional project skills

Use the scaffold Step 1 answer on extra project skills; ask the user only if scaffold Step 1 did not settle it. Candidates:
- `api-migrate` — Alembic migration with safety gate (if SQLAlchemy/Alembic is wired up)
- `api-endpoint` — scaffold a new router + schema + service method

For each workflow the user named, create a skill in `.claude/skills/` and add a row to the `AGENTS.md` Skills table.

---

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Use the scaffold Step 1 answer on `CLAUDE.md`; ask only if scaffold Step 1 did not settle it. Skip this step if the user does not use Claude Code.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` into every Claude Code session; keep everything else in `AGENTS.md`.

Step E, in the finish step below, hashes it into `seeded_files`.

### 8. Task management (optional)

Use the scaffold Step 1 answer on task management; ask only if scaffold Step 1 did not settle it. If yes, append the task-management section to the project's `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/fastapi/template-tail/task-management.md" >> AGENTS.md
```

#### Finish the harness (required, whatever the answer above)

Execute kit Steps **E through H** using the **fastapi** row: harness.json (Step E, with the `api-verify` hash), the base snapshot (E2), per-folder documentation (E3), the `.agents` symlink (F), the AGENTS.md tail and final format pass (G) and plugin install (H). The scaffold is not finished until Step H is done.

### 9. Remove example code (optional)

Use the scaffold Step 1 answer on removing example code; ask only if scaffold Step 1 did not settle it. If yes, once the project is verified, use the cleanup utility — load it with: `cat "<skill-dir>/../cleanup/SKILL.md"`.

FastAPI-specific steps (the skill covers these):
- Delete `src/api/routers/example.py`, `src/api/schemas/request/example.py`, `src/api/schemas/response/example.py`, `src/api/services/example.py`, `test/test_api/test_example.py`
- Remove `example` import and `include_router` from `src/api/routes.py`
- Remove `EXAMPLE` from `APITags` in `src/api/tags.py`

---

## Rules

- Install dependencies inside the project virtual environment, not globally, so the project stays isolated
- **Never** commit `src/.env` or put secrets in generated `AGENTS.md` / `CLAUDE.md`
- Verify the API starts and Swagger docs render before handing off; remove example code only after the user confirms the project runs
- Leave `__pycache__/`, `log/`, `src/.env` and `.venv/` out of the files you write; they are local artefacts
- The scaffold is complete only once the project `AGENTS.md` exists; check for it before handing off
- Keep `conftest.py` and `factories/` when removing example code; they are shared test infrastructure
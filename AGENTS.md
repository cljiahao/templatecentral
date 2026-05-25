<!-- templateCentral: plugin@4.0.0 -->
# AGENTS.md — templateCentral

templateCentral is a Claude Code plugin — a skill library for scaffolding production-ready apps. This is NOT an application itself.

## Stack Detection

Detect from project files before routing. Look in a subdirectory if needed (e.g., `backend/`, `frontend/`):

| Signal | Stack |
|--------|-------|
| `next.config.*` | nextjs |
| `vite.config.*` (with React) | vite-react |
| `requirements.txt` + fastapi import | fastapi |
| `nest-cli.json` or `@nestjs/core` in package.json | nestjs |

If ambiguous → ask. Meta-tasks (auditing templateCentral itself) stay with the orchestrator.

## Skill Routing

| Intent | Skill |
|--------|-------|
| New project from scratch | `templatecentral:scaffold` |
| Add capability to existing project | `templatecentral:add` |
| DB migration or framework upgrade | `templatecentral:migrate` |
| Verify build compiles | `templatecentral:build` |
| Write and run tests | `templatecentral:test` |
| Code review | `templatecentral:review` |
| Standards drift check / validation patterns | `templatecentral:standards` |
| Full ecosystem + accuracy audit | `templatecentral:audit` |
| Remove example code / task planning | `templatecentral:cleanup` |
| Write a new templateCentral skill | `templatecentral:write-skill` |

## `templatecentral:add` capabilities

`auth` · `database` · `page` · `feature` · `module` · `api-route` · `endpoint` · `component` · `form` · `integration` · `test` · `logging` · `error-handling` · `pagination` · `mutation` · `ai-security`

## Working on this repo

- All skill files: `skills/` — read `skills/CONVENTIONS.md` before editing any skill
- Lint gate: `bash scripts/lint-skills.sh skills/` — must pass before any commit
- Write new skills: `templatecentral:write-skill`
- PostToolUse hook: `bash scripts/lint-skills.sh skills/ 2>&1 | tail -10` runs after every Edit/Write — feedback only

## Rules

- NEVER commit, push, or deploy without explicit user instruction
- NEVER delete user code without confirmation
- NEVER remove or ignore lockfiles without explicit user approval
- NEVER scaffold into a non-empty target directory without explicit user confirmation
- NEVER modify `.claude/`, `~/.claude/`, or shell config outside this repo
- Trace capture stays OFF by default everywhere

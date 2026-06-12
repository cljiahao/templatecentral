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
| Adopt an existing project / retrofit the harness into a project built without templateCentral | `templatecentral:migrate` |
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

## Skill Scoping Model

templateCentral seeds project-scoped skills into every scaffolded project. Understanding the resolution order is important:

| Level | Location | Invoked as | Priority |
|-------|----------|------------|----------|
| Managed | org-wide managed settings | `/<name>` | highest |
| CLI flag | `--agents` session flag | session-only | 2nd |
| User | `~/.claude/skills/` | `/<name>` | personal (overrides project on name collision) |
| Project | `.claude/skills/` | `/<name>` | project-specific (loses to user) |
| Plugin | `<plugin>/skills/` | `<plugin>:<name>` | namespaced, no conflict |

**Key facts:**
- Plugin skills (`templatecentral:*`) are namespaced — they never conflict with project or user skills
- Project skills (`.claude/skills/`) are invoked without namespace (e.g., `/next-verify`); per current official docs, user (personal) skills override project skills when names collide — name seeded project skills distinctively to avoid collisions
- A project skill is a **directory** with `SKILL.md` as its entrypoint (`.claude/skills/<name>/SKILL.md`) — flat `.claude/skills/<name>.md` files are silently ignored
- templateCentral seeds project skills for project-specific workflows; the scaffolded AGENTS.md instructs agents to check `.claude/skills/` first for project workflows, then use `templatecentral:*` for framework-level operations
- As the project grows, agents should create new project skills for any workflow repeated more than once

## CLAUDE.md and subagents

`CLAUDE.md` = `@AGENTS.md` — Claude Code expands this fully at session start for the main agent.

**Subagent blind spot (v2.1.84+):** Built-in subagents (`/explore`, `/plan`) have `omitClaudeMd: true` — they do not receive CLAUDE.md or its `@AGENTS.md` import. AGENTS.md must therefore be self-contained and not rely on CLAUDE.md being loaded. All routing instructions belong in AGENTS.md, not CLAUDE.md.

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

<!-- templateCentral: plugin@5.0.0 -->
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

If ambiguous → ask. For a **new** project with no stack named, `templatecentral:scaffold` recommends one from the use-case (see its Step 0) — don't guess. Meta-tasks (auditing templateCentral itself) stay with the orchestrator.

## Skill Routing

| Intent | Skill |
|--------|-------|
| New project from scratch | `templatecentral:scaffold` |
| Add capability to existing project | `templatecentral:add` |
| Adopt an existing project / retrofit the harness into a project built without templateCentral | `templatecentral:migrate` |
| DB migration or framework upgrade | `templatecentral:migrate` |
| Verify build compiles | build utility (`cat skills/build/SKILL.md` via plugin root) |
| Write and run tests | test utility (`cat skills/test/SKILL.md` via plugin root) |
| Code review | review utility (`cat skills/review/SKILL.md` via plugin root) |
| Standards drift check / validation patterns | `templatecentral:standards` |
| Full ecosystem + accuracy audit (repo-internal) | `/tc-audit` (project skill in `.claude/skills/`) |
| Remove example code / task planning | cleanup utility (`cat skills/cleanup/SKILL.md` via plugin root) |
| Write a new templateCentral skill (repo-internal) | `/tc-write-skill` (project skill in `.claude/skills/`) |

## `templatecentral:add` capabilities

`auth` · `database` · `page` · `feature` · `endpoint` · `form` · `integration` · `test` · `logging` · `error-handling` · `pagination` · `mutation-testing` · `ai-security`

(aliases accepted: `api-route`, `module` → endpoint; `component` → feature; `mutation` → mutation-testing)

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

## Cross-tool portability

**Claude Code is the primary, non-negotiable target** (marketplace install + full `.claude/hooks/` harness). Beyond that, templateCentral rides two cross-vendor open standards so its skills also work in OpenCode, Codex, and Antigravity unchanged — keep contributions on-standard:

- **SKILL.md is portable.** Reference bundled/sibling files only via the `<skill-dir>` placeholder — the skill's own directory, which every compliant tool surfaces to the agent at invocation (CC/OpenCode print "Base directory for this skill", Codex injects the skill's `(file: …)` path). NEVER hardcode `$HOME/.claude/plugins/…` and NEVER use `${CLAUDE_SKILL_DIR}` (empty in agent-run ```bash``` blocks — CC only fills it for `!`-injection). Lint-enforced. See `skills/CONVENTIONS.md` §1.
- **AGENTS.md is the universal layer** (Linux Foundation / Agentic AI Foundation standard) — read natively by Codex/Antigravity and by Claude Code via the `CLAUDE.md = @AGENTS.md` import. Push durable routing/constraints here, not into CC-only surfaces.
- **What stays CC-specific:** the in-agent live guards (`.claude/hooks/` + `settings.json`). The git-hook/CI half of the harness (lefthook + gitleaks + CI) is already tool-agnostic. Cross-tool support is strictly additive — it must never regress the Claude Code experience. Full analysis + per-tool adapter roadmap: `FUTURE.md` §6.

## Working on this repo

- All skill files: `skills/` — read `skills/CONVENTIONS.md` before editing any skill
- Lint gate: `bash scripts/lint-skills.sh skills/` — must pass before any commit
- Write new skills: `/tc-write-skill` (repo-internal project skill in `.claude/skills/`)
- PostToolUse hook: `bash scripts/lint-skills.sh skills/ 2>&1 | tail -10` runs after every Edit/Write — feedback only

## Rules

- NEVER commit, push, or deploy without explicit user instruction
- NEVER delete user code without confirmation
- NEVER remove or ignore lockfiles without explicit user approval
- NEVER scaffold into a non-empty target directory without explicit user confirmation
- NEVER modify `.claude/`, `~/.claude/`, or shell config outside this repo
- Trace capture stays OFF by default everywhere

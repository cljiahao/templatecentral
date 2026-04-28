# templateCentral

Production-ready project scaffolding for **Next.js**, **Vite + React**, **FastAPI**, and **NestJS**. Install once as a Claude Code plugin — scaffold anywhere without cloning the repo.

## Install

```bash
claude plugin marketplace add templatecentral
```

That's it. The plugin registers 46 skills that Claude Code picks up automatically.

## Usage

Ask Claude to scaffold a project:

> "Scaffold a new Next.js project at ~/projects/my-app"
> "Create a FastAPI API at ~/Desktop/my-api"
> "Set up a NestJS backend in ~/work/my-service"
> "Scaffold a Vite React SPA at ~/projects/my-spa"

Claude reads the appropriate scaffold skill, creates every file verbatim or from precise generation rules, installs dependencies, runs the verification gate, and writes a project `AGENTS.md` — all in one shot.

## Available Skills (46)

Skills are organized by stack. Each skill has YAML frontmatter (`name`, `description`).

| Stack | Skills |
|-------|--------|
| **Next.js** (11) | scaffold, code-standards, add-feature, add-page, add-api-route, add-component, add-integration, add-auth, add-test, add-form, add-database |
| **FastAPI** (7) | scaffold, code-standards, add-endpoint, add-test, add-auth, add-database, add-integration |
| **Vite + React** (9) | scaffold, code-standards, add-feature, add-page, add-component, add-integration, add-auth, add-test, add-form |
| **NestJS** (7) | scaffold, code-standards, add-module, add-test, add-auth, add-database, add-integration |
| **Shared** (12) | add-error-handling, add-logging, add-pagination, build-agent, drift-check, full-stack-pairing, remove-example, review-agent, task-management, test-agent, update-agent, validation-patterns |

## Repository Structure

```
templateCentral/
├── AGENTS.md                       # Agent orchestration guide
├── README.md
├── .claude-plugin/                 # Plugin manifest
│   ├── plugin.json                 # v2.1.0 — lists all 46 skills
│   └── marketplace.json
├── skills/                         # All 46 skills (flat <stack>-<skill> naming)
│   ├── nextjs-scaffold/SKILL.md
│   ├── fastapi-scaffold/SKILL.md
│   ├── nestjs-scaffold/SKILL.md
│   ├── vite-react-scaffold/SKILL.md
│   └── ... (42 more)
└── docs/
    └── superpowers/                # Implementation plans and specs
```

## Adding a New Skill

To contribute a new skill:

1. Create `skills/<stack>-<skill>/SKILL.md` with frontmatter (`name`, `description`)
2. Add the skill name to `.claude-plugin/plugin.json` under `"skills"`
3. Create `.claude/rules/<stack>.md` if a new stack is added
4. Open a PR

## Recommended Plugins

None are required — install as needed. All are Claude Code plugins unless noted as MCP.

| Plugin | Install | When to use | When to skip / turn off |
|--------|---------|-------------|--------------------------|
| **caveman** | `claude plugin marketplace add JuliusBrussee/caveman` | Exploration, audits, Q&A, code-building (65–75% fewer output tokens) | Any session writing committed files (`SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`) — compresses prose, degrades instruction quality |
| **superpowers** | `claude plugin marketplace add obra/superpowers` | Features touching 3+ files or architectural decisions: brainstorm → plan → implement | One-liners, scaffolding, or "just do it" tasks |
| **claude-mem** | `claude plugin marketplace add thedotmack/claude-mem` then `claude plugin install claude-mem` | Scaffolded projects — auto-captures tool usage, decisions, and file changes across sessions via SQLite + vector DB | templateCentral itself — use built-in markdown memory here instead (curated, auditable) |
| **codegraph** | `npx @colbymchenry/codegraph` (Node 18+) | "What calls X / where does Y live" — add when grepping for definitions is a regular cost | Fresh scaffolds (< 5 features); structure is predictable from template |
| **graphify** | `uv tool install graphifyy && graphify install` (Python 3.10+) | Codebase structure overview (communities, god nodes); use before codegraph for high-level orientation | Same threshold as codegraph |
| **code-review-graph** | `pip install code-review-graph && code-review-graph install && code-review-graph build` (Python 3.10+) | PRs and refactors with non-obvious blast radius — queries callers, dependents, covering tests | Routine single-file edits |

### Install order

```bash
# Day one (Claude Code plugins)
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add obra/superpowers

# For scaffolded projects (not templateCentral itself — use built-in memory here)
claude plugin marketplace add thedotmack/claude-mem
claude plugin install claude-mem

# After 5+ features (MCP servers — run inside your project)
npx @colbymchenry/codegraph                                              # codegraph
uv tool install graphifyy && graphify install                            # graphify
pip install code-review-graph && code-review-graph install && code-review-graph build  # code-review-graph

# When doing refactors or PRs — activate code-review-graph
```

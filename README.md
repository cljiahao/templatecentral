# templatecentral

Production-ready project scaffolding for **Next.js**, **Vite + React**, **FastAPI**, and **NestJS**. Install once as a Claude Code plugin — scaffold anywhere without cloning the repo.

## Install

### From GitHub (available now)

Push this repo to GitHub, then anyone can install directly from your GitHub username/repo:

```bash
# Add your GitHub repo as a marketplace source
claude plugin marketplace add cljiahao/templatecentral

# Then install the plugin
claude plugin install templatecentral
```

The `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` files are already included — no extra setup needed.

### From the Official Marketplace (once published)

If listed on the Anthropic plugin marketplace, users can install with a single command:

```bash
claude plugin marketplace add templatecentral
```

To submit for listing: https://clau.de/plugin-directory-submission

---

Either way, the plugin registers 46 skills that Claude Code picks up automatically.

## Updating

```bash
claude plugin update templatecentral
```

This pulls the latest version from the source it was installed from (GitHub or the official marketplace). Run it whenever new skills or fixes are released.

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
templatecentral/
├── AGENTS.md                       # Agent orchestration guide
├── README.md
├── .claude-plugin/                 # Plugin manifest
│   ├── plugin.json                 # v2.1.0 — lists all 46 skills
│   └── marketplace.json
└── skills/                         # All 46 skills (flat <stack>-<skill> naming)
    ├── nextjs-scaffold/SKILL.md
    ├── fastapi-scaffold/SKILL.md
    ├── nestjs-scaffold/SKILL.md
    ├── vite-react-scaffold/SKILL.md
    └── ... (42 more)
```

## Adding a New Skill

To contribute a new skill:

1. Create `skills/<stack>-<skill>/SKILL.md` with frontmatter (`name`, `description`)
2. Add the skill name to `.claude-plugin/plugin.json` under `"skills"`
3. Create `.claude/rules/<stack>.md` if a new stack is added
4. Open a PR

## Recommended Plugins

**superpowers is strongly recommended** — templatecentral integrates with the superpowers brainstorm → plan → execute workflow for complex multi-file features. The others are optional but recommended.

| Plugin | Install | When to use | When to skip / turn off |
|--------|---------|-------------|--------------------------|
| **superpowers** ⭐ recommended | `claude plugin marketplace add obra/superpowers` | Complex features (3+ files) — provides brainstorm → plan → execute workflow that templatecentral skills reference | Simple one-file edits |
| **caveman** | `claude plugin marketplace add JuliusBrussee/caveman` | Exploration, audits, Q&A, code-building (65–75% fewer output tokens) | Any session writing committed files (`SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`) — compresses prose, degrades instruction quality |
| **claude-mem** | `claude plugin marketplace add thedotmack/claude-mem` then `claude plugin install claude-mem` | Scaffolded projects — auto-captures tool usage, decisions, and file changes across sessions via SQLite + vector DB | templatecentral itself — use built-in markdown memory here instead (curated, auditable) |

```bash
# Strongly recommended
claude plugin marketplace add obra/superpowers

# Optional
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add thedotmack/claude-mem
claude plugin install claude-mem
```

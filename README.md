# templatecentral
**One prompt. Four stacks. Production-ready every time.**

[![GitHub Stars](https://img.shields.io/github/stars/cljiahao/templatecentral?style=flat-square&logo=github)](https://github.com/cljiahao/templatecentral/stargazers)
[![Version](https://img.shields.io/badge/version-2.1.0-blue?style=flat-square)](https://github.com/cljiahao/templatecentral)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-blueviolet?style=flat-square)](https://github.com/cljiahao/templatecentral)

<!-- DEMO: Replace this comment block with a GIF once you have a recording.
     Recommended: ~30s clip of Claude responding to "Scaffold a Next.js project at ~/projects/my-app"
     from blank terminal to working app.
     <img src="docs/assets/demo.gif" alt="templatecentral demo" width="100%" /> -->

---

## Before / After

| Without templatecentral | With templatecentral |
|:---|:---|
| Pick a starter template, strip boilerplate | `"Scaffold a Next.js project at ~/projects/my-app"` |
| Configure TypeScript, ESLint, and Prettier by hand | App Router, shadcn/ui, TanStack Query — wired and working |
| Set up Docker, Vitest, and Husky pre-commit hooks | Docker, Vitest, Husky — done |
| Write project docs for your AI agent | `AGENTS.md` + `CLAUDE.md` written automatically |
| ~45 minutes of setup decisions | ~60 seconds, zero decisions |

---

## Install

### From GitHub (available now)

```bash
claude plugin marketplace add cljiahao/templatecentral
claude plugin install templatecentral
```

### From the Official Marketplace *(coming soon)*

```bash
claude plugin marketplace add templatecentral
```

Either way, 46 skills are registered automatically — no extra setup.

### Updating

```bash
claude plugin update templatecentral
```

---

## Usage

Ask Claude to scaffold a project:

```
"Scaffold a new Next.js project at ~/projects/my-app"
"Create a FastAPI API at ~/Desktop/my-api"
"Set up a NestJS backend in ~/work/my-service"
"Scaffold a Vite React SPA at ~/projects/my-spa"
```

Claude reads the scaffold skill, generates every file, installs dependencies, runs verification gates, and writes `AGENTS.md` — all in one shot.

---

## What You Get

Each scaffold produces a complete, working project — not a bare starter.

### Next.js
✅ App Router + TypeScript · ✅ shadcn/ui + Tailwind CSS v4 · ✅ TanStack Query · ✅ React Hook Form + Zod
✅ Prettier + ESLint + Husky pre-commit · ✅ Vitest + coverage · ✅ Docker · ✅ `.env.example` · ✅ `AGENTS.md` + `CLAUDE.md`

### Vite + React
✅ React 18 + React Router v7 · ✅ TanStack Query · ✅ React Hook Form + Zod · ✅ Tailwind CSS v4
✅ Vitest + Testing Library · ✅ Prettier + ESLint + Husky · ✅ `AGENTS.md` + `CLAUDE.md`

### FastAPI
✅ FastAPI + Uvicorn + Pydantic v2 · ✅ Structured JSON logging · ✅ Ruff + Mypy
✅ pytest + httpx (async) · ✅ python-dotenv · ✅ `AGENTS.md` + `CLAUDE.md`

### NestJS
✅ NestJS + Fastify · ✅ Swagger docs · ✅ nestjs-pino + nestjs-zod · ✅ Jest + e2e tests
✅ Prettier + ESLint + Husky · ✅ `AGENTS.md` + `CLAUDE.md`

> Auth, database, pages, components, API routes, and integrations are added via separate skills — keeping the base clean.

---

## Available Skills (46)

| Stack | Skills |
|-------|--------|
| **Next.js** (11) | scaffold, code-standards, add-feature, add-page, add-api-route, add-component, add-integration, add-auth, add-test, add-form, add-database |
| **Vite + React** (9) | scaffold, code-standards, add-feature, add-page, add-component, add-integration, add-auth, add-test, add-form |
| **FastAPI** (7) | scaffold, code-standards, add-endpoint, add-test, add-auth, add-database, add-integration |
| **NestJS** (7) | scaffold, code-standards, add-module, add-test, add-auth, add-database, add-integration |
| **Shared** (12) | add-error-handling, add-logging, add-pagination, build-agent, drift-check, full-stack-pairing, remove-example, review-agent, task-management, test-agent, update-agent, validation-patterns |

---

## Works With

**[superpowers](https://github.com/obra/superpowers) is strongly recommended** — templatecentral integrates with the superpowers brainstorm → plan → execute workflow for complex multi-file features.

```bash
claude plugin marketplace add obra/superpowers
```

| Task complexity | Workflow |
|:---|:---|
| Simple (1–2 files) | templatecentral skill directly |
| Complex (3+ files, architectural decisions) | superpowers brainstorm → plan → execute |

**Optional plugins:**

| Plugin | Install | When to use |
|--------|---------|-------------|
| **caveman** | `claude plugin marketplace add JuliusBrussee/caveman` | Reduce output tokens during exploration and Q&A |
| **claude-mem** | `claude plugin marketplace add thedotmack/claude-mem` | Persist session context across scaffolded projects |

---

## Repository Structure

```
templatecentral/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest — lists all 46 skills
│   └── marketplace.json     # Anthropic marketplace metadata
├── skills/                  # All 46 skills (flat <stack>-<skill> naming)
│   ├── nextjs-scaffold/SKILL.md
│   ├── fastapi-scaffold/SKILL.md
│   └── ... (44 more)
└── AGENTS.md                # Agent orchestration guide
```

---

## Adding a New Skill

Contributions welcome — especially new stacks and coverage gaps.

1. Create `skills/<stack>-<skill>/SKILL.md` with frontmatter (`name`, `description`)
2. Add the skill name to `.claude-plugin/plugin.json` under `"skills"`
3. If adding a new stack, create `.claude/rules/<stack>.md`
4. Open a PR — CI will validate your skill's frontmatter automatically

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

---

## ⭐ Star This Repo

If templatecentral saves you setup time, a star helps others find it.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=cljiahao/templatecentral&type=Date)](https://star-history.com/#cljiahao/templatecentral&Date)

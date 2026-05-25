# templatecentral
**One prompt. Four stacks. Production-ready every time.**

[![GitHub Stars](https://img.shields.io/github/stars/cljiahao/templatecentral?style=flat-square&logo=github)](https://github.com/cljiahao/templatecentral/stargazers)
[![Version](https://img.shields.io/badge/version-4.0.0-blue?style=flat-square)](https://github.com/cljiahao/templatecentral)
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

Either way, 10 skills are registered automatically — no extra setup.

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
✅ React 19 + React Router v7 · ✅ TanStack Query · ✅ React Hook Form + Zod · ✅ Tailwind CSS v4
✅ Vitest + Testing Library · ✅ Prettier + ESLint + Husky · ✅ `AGENTS.md` + `CLAUDE.md`

### FastAPI
✅ FastAPI + Uvicorn + Pydantic v2 · ✅ Structured JSON logging · ✅ Ruff + Mypy
✅ pytest + httpx (async) · ✅ python-dotenv · ✅ `AGENTS.md` + `CLAUDE.md`

### NestJS
✅ NestJS + Fastify · ✅ Swagger docs · ✅ nestjs-pino + nestjs-zod · ✅ Vitest + e2e tests
✅ Prettier + ESLint + Husky · ✅ `AGENTS.md` + `CLAUDE.md`

> Auth, database, pages, components, API routes, and integrations are added via separate skills — keeping the base clean.

---

## Available Skills (10)

**User-invocable (6):**

| Skill | What it does |
|-------|-------------|
| `templatecentral:scaffold` | Scaffold a new Next.js, Vite+React, FastAPI, or NestJS project from scratch |
| `templatecentral:add` | Add any capability to an existing project — auth, database, tests, components, pages, API routes, forms, logging, error handling, pagination, integrations, and more |
| `templatecentral:standards` | Review code quality, naming conventions, validation patterns, drift, and full-stack type contracts |
| `templatecentral:migrate` | Run database migrations or migrate a project to updated conventions, dependencies, or patterns |
| `templatecentral:audit` | Full project audit — ecosystem research, mechanical lint, per-file semantic review, and fix loop |
| `templatecentral:write-skill` | Author new skills, enforcing CONVENTIONS.md at creation time |

**Agent utilities (4)** — loaded internally by agents, not invoked directly by users:

| Skill | What it does |
|-------|-------------|
| `build` | Detect stack, run the build command, report failures without auto-fixing |
| `test` | Write tests for newly added code and run the full test suite |
| `review` | Analyse code quality and flag issues, or apply review feedback and fix flagged issues |
| `cleanup` | Remove example code or manage task scaffolding after a feature is complete |

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

---

## Repository Structure

```
templatecentral/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (points to skills/)
│   └── marketplace.json     # Anthropic marketplace metadata
├── skills/                  # All skills — nested reference file architecture
│   ├── CONVENTIONS.md       # Single source of truth for skill authoring rules
│   ├── scaffold/SKILL.md    # Router → skills/scaffold/<stack>/
│   ├── add/SKILL.md         # Router → skills/add/<capability>/<stack>.md
│   ├── standards/SKILL.md   # Router → skills/standards/<check>/
│   ├── migrate/SKILL.md     # Router → skills/migrate/<type>/
│   ├── audit/SKILL.md       # Router → skills/audit/implementation.md
│   └── write-skill/SKILL.md
└── AGENTS.md                # Agent orchestration guide
```

---

## Adding a New Skill

Contributions welcome — especially new stacks and coverage gaps.

1. Read `skills/CONVENTIONS.md` — it defines all nesting rules, description limits, and ref header formats
2. Use `templatecentral:write-skill` — it walks through the authoring checklist and validates your skill before you open a PR
3. If adding a new stack, create `.claude/rules/<stack>.md`
4. Open a PR — CI will run `scripts/lint-skills.sh` to validate your skill automatically

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

---

## ⭐ Star This Repo

If templatecentral saves you setup time, a star helps others find it.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=cljiahao/templatecentral&type=Date)](https://star-history.com/#cljiahao/templatecentral&Date)

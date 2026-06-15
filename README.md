# templatecentral
**One prompt. Four stacks. Production-ready every time.**

[![GitHub Stars](https://img.shields.io/github/stars/cljiahao/templatecentral?style=flat-square&logo=github)](https://github.com/cljiahao/templatecentral/stargazers)
[![Version](https://img.shields.io/badge/version-5.1.0-blue?style=flat-square)](https://github.com/cljiahao/templatecentral)
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

### From the community marketplace *(coming soon)*

Once approved for Anthropic's community marketplace, install with:

```bash
claude plugin install templatecentral@claude-community
```

Either way, all 8 skills are available automatically — no extra setup.

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

**Every stack includes:**
✅ AI harness — **7-event hook kit** seeded as `.claude/hooks/` scripts: `UserPromptSubmit` injection + credential firewall, `PreToolUse` secrets read/write guard + git guards, `PostToolUse` type-check, `PostToolUseFailure` error surface, `Stop` test gate, `SubagentStop` type-gate, `SessionStart` context recovery (re-injects AGENTS.md + `docs/CONSTITUTION.md` after compaction). `permissions.deny` blocks reading `.env*` and `secrets/**`. Self-contained — enforces even after plugin uninstall.  
✅ `AGENTS.md` + `CLAUDE.md` · ✅ `.agents → .claude` symlink for cross-framework compatibility

### Next.js
✅ App Router + TypeScript · ✅ shadcn/ui + Tailwind CSS v4 · ✅ TanStack Query · ✅ React Hook Form + Zod  
✅ Prettier + ESLint + Husky · ✅ Vitest + coverage · ✅ Docker · ✅ `.env.example`

### Vite + React
✅ React 19 + React Router v7 · ✅ TanStack Query · ✅ React Hook Form + Zod · ✅ Tailwind CSS v4  
✅ Vitest + Testing Library · ✅ Prettier + ESLint + Husky

### FastAPI
✅ FastAPI + Uvicorn + Pydantic v2 · ✅ Structured JSON logging · ✅ Ruff + Pyright  
✅ pytest + httpx (async) · ✅ python-dotenv

### NestJS
✅ NestJS + Fastify · ✅ Swagger docs · ✅ nestjs-pino + nestjs-zod · ✅ Vitest + e2e tests  
✅ Prettier + ESLint + Husky

> Add capabilities via `templatecentral:add` — `auth · database · page · feature · endpoint · form · integration · test · logging · error-handling · pagination · mutation-testing · ai-security` — keeping the base scaffold clean.

---

## Available Skills (8)

**User-invocable (4):**

| Skill | What it does |
|-------|-------------|
| `templatecentral:scaffold` | Scaffold a new Next.js, Vite+React, FastAPI, or NestJS project from scratch |
| `templatecentral:add` | Add any capability to an existing project — auth, database, tests, components, pages, API routes, forms, logging, error handling, pagination, integrations, and more |
| `templatecentral:standards` | Review code quality, naming conventions, validation patterns, drift, and full-stack type contracts |
| `templatecentral:migrate` | Run database migrations, migrate a project to updated conventions, or **adopt/retrofit the harness** into a project that was built without templateCentral |

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

## Scheduled Loops

Two monthly GitHub Actions workflows keep templateCentral accurate without manual effort:

- **`ecosystem-refresh`** — re-scans framework release notes, library changelogs, and OWASP updates; opens a PR to update `.claude/audit-ecosystem-research.md` and any stale version pins.
- **`scaffold-verify`** — scaffolds a test project from each template and runs its build + test gate, catching regressions before they reach users.

Both workflows require an `ANTHROPIC_API_KEY` repository secret. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup details.

---

## Repository Structure

```
templatecentral/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (points to skills/)
│   └── marketplace.json     # Anthropic marketplace metadata
├── .github/workflows/       # CI — lint-skills, validate-manifest, AI PR review
├── scripts/
│   ├── lint-skills.sh       # Mechanical pattern checks for all skill files
│   ├── validate-manifest.sh # Validates plugin.json + marketplace.json before publish
│   └── pre-guard.sh         # PreToolUse hook — blocks writes to secrets and CI pipeline files
├── skills/                  # Shipped skills — nested reference file architecture
│   ├── CONVENTIONS.md       # Single source of truth for skill authoring rules
│   ├── scaffold/SKILL.md    # Router → skills/scaffold/<stack>/
│   ├── add/SKILL.md         # Router → skills/add/<capability>/<stack>.md
│   ├── standards/SKILL.md   # Router → skills/standards/<check>/
│   ├── migrate/SKILL.md     # Router → skills/migrate/<type>/
│   ├── build/               # (de-registered utility) detect stack + run build command
│   ├── test/                # (de-registered utility) write and run tests
│   ├── review/              # (de-registered utility) code review + apply feedback
│   └── cleanup/             # (de-registered utility) remove example code / task scaffolding
├── .claude/skills/          # Repo-internal contributor skills (NOT shipped to installs)
│   ├── audit/               # /tc-audit — full ecosystem + accuracy audit
│   └── write-skill/         # /tc-write-skill — skill authoring checklist
├── AGENTS.md                # Agent orchestration guide
└── CHANGELOG.md             # Full version history
```

---

## Adding a New Skill

Contributions welcome — especially new stacks and coverage gaps.

1. Read `skills/CONVENTIONS.md` — it defines all nesting rules, description limits, and ref header formats
2. Use `/tc-write-skill` — it walks through the authoring checklist and validates your skill before you open a PR

> **Contributor-only skills.** `/tc-write-skill` (authoring) and `/tc-audit` (full ecosystem + accuracy audit) live in this repo under `.claude/skills/` and are available as project skills when you clone and open the repo. They are **not** shipped to installed projects — end users never carry the plugin's maintenance tooling.
3. If adding a new stack, create `.claude/rules/<stack>.md`
4. Run `bash scripts/lint-skills.sh skills/` and `bash scripts/validate-manifest.sh` locally — both must pass
5. Open a PR — CI will run both scripts automatically

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

---

## ⭐ Star This Repo

If templatecentral saves you setup time, a star helps others find it.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=cljiahao/templatecentral&type=Date)](https://star-history.com/#cljiahao/templatecentral&Date)

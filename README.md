# templatecentral
**One prompt. Four stacks. Production-ready every time.**

[![GitHub Stars](https://img.shields.io/github/stars/cljiahao/templatecentral?style=flat-square&logo=github)](https://github.com/cljiahao/templatecentral/stargazers)
[![Version](https://img.shields.io/badge/version-6.1.2-blue?style=flat-square)](https://github.com/cljiahao/templatecentral)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-blueviolet?style=flat-square)](https://github.com/cljiahao/templatecentral)

<!-- DEMO: Replace this comment block with a GIF once you have a recording.
     Recommended: ~30s clip of Claude responding to "Scaffold a Next.js project at ~/projects/my-app"
     from blank terminal to working app.
     <img src="docs/assets/demo.gif" alt="templatecentral demo" width="100%" /> -->

templatecentral is a Claude Code plugin that turns one prompt into a production-ready Next.js, Vite + React, FastAPI or NestJS project — and ships a guard layer that keeps the AI agent inside the rules you set, for the life of the project. The rules are enforced by hooks and CI, checked for tampering, and upgradeable without losing your own.

---

## Why templatecentral

An AI agent follows written rules most of the time, and "most of the time" is not a control. A `CLAUDE.md` asks; nothing makes the agent comply. The same gaps show up in every team:

- **Rules erode quietly.** An agent under pressure runs `git commit --no-verify`, sets `HUSKY=0`, or edits the hook that blocked it.
- **Hooks have blind spots.** A typical branch guard reads the session's starting folder. In a git worktree that is the wrong branch, so it either blocks good work or lets a commit to `main` through.
- **Context gets lost.** After a long session compacts, the agent forgets the project's invariants and keeps working without them.
- **Security is left for later.** Starter templates ship authentication but no authorization, no dependency audit, and secrets one `Write` away.
- **Setups drift.** Each project copies hooks by hand, tweaks them, and can never take an upstream fix without losing its own changes.

templatecentral closes each of these, in every project it scaffolds or adopts.

### Every change clears six checkpoints

| # | Checkpoint | What it does |
|:-:|:---|:---|
| 1 | **Prompt** (`UserPromptSubmit`) | Blocks prompt-injection phrases and pasted credentials before the model sees them |
| 2 | **Before each tool** (`PreToolUse`) | Secrets hard-blocked · CI and governance edits ask a human · git hook bypasses blocked |
| 3 | **After each edit** (`PostToolUse`) | Type-check and comment-hygiene feedback straight back to the agent |
| 4 | **Before the agent stops** (`Stop`, `SubagentStop`) | Tests must pass before a turn ends; types must pass before a subagent returns |
| 5 | **Commit and push** (git hooks) | Commit-message format and pre-commit checks; pre-push re-checks the harness hashes |
| 6 | **Pull request** (CI gates) | Secret scan, dependency audit, harness integrity — no label bypass |

Across all six, **context recovery** (`SessionStart`) re-injects `AGENTS.md` routing and `docs/CONSTITUTION.md` on start, resume, clear and compact, so the rules survive long sessions. Checkpoints 5 and 6 run in git and CI, so they still hold when someone works without the agent.

---

## Before / After

| Without templatecentral | With templatecentral |
|:---|:---|
| Pick a starter template, strip boilerplate | `"Scaffold a Next.js project at ~/projects/my-app"` |
| Configure TypeScript, ESLint, and Prettier by hand | App Router, shadcn/ui, TanStack Query — wired and working |
| Set up Docker, Vitest, and lefthook pre-commit hooks | Docker, Vitest, lefthook — done |
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

Either way, the four skills (plus four internal agent utilities) are available immediately — no extra setup.

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

Not sure which stack? Just ask — e.g. *"scaffold me a new app"* — and Claude asks a couple of use-case questions, then recommends one of the four stacks before generating.

Claude reads the scaffold skill, generates every file, installs dependencies, runs verification gates, and writes `AGENTS.md` — all in one shot.

Already have a project? Ask Claude to run `templatecentral:migrate`. It adopts the harness, reuses your pipelines where they already run a check, and keeps your own rules in `.claude/hooks/local/`. A human then reviews and re-blesses the harness hashes — agents never regenerate them.

---

## What You Get

Each scaffold produces a complete, working project — not a bare starter.

**Every stack includes:**
✅ AI harness — a **6-event hook kit** in `.claude/hooks/`: prompt-injection + inline-credential firewall (`UserPromptSubmit`), secrets/CI-pipeline write guard and git guards that block `--no-verify` and its equivalents (`LEFTHOOK=0`, `core.hooksPath`) (`PreToolUse`), type-check feedback (`PostToolUse`), test gate (`Stop`), type gate (`SubagentStop`), and context recovery after compaction (`SessionStart`). `permissions.deny` blocks reading `.env`-style secret files, keys, and `secrets/`. Self-contained — keeps enforcing after plugin uninstall.  
✅ Integrity manifest — `.claude/harness.json` holds a SHA-256 of every enforcement file, re-checked on pre-push and in CI; only a human re-blesses it.  
✅ Shared CI gates — one `.claude/ci-gates.sh` (secret scan, dependency audit, changelog, README and comment checks) called by both GitHub Actions and Azure Pipelines.  
✅ `AGENTS.md` + `CLAUDE.md` + `docs/CONSTITUTION.md` · ✅ `.agents → .claude` symlink for cross-framework compatibility · ✅ Git Workflow convention — always branch from a freshly fetched `main` (`git fetch -p` + `git pull --ff-only`)

### Next.js
✅ App Router + TypeScript · ✅ shadcn/ui + Tailwind CSS v4 · ✅ TanStack Query · ✅ React Hook Form + Zod  
✅ Prettier + ESLint (hard comment gate) + lefthook · ✅ Vitest + coverage · ✅ Docker · ✅ `.env.example`

### Vite + React
✅ React 19 + React Router v8 · ✅ TanStack Query · ✅ React Hook Form + Zod · ✅ Tailwind CSS v4  
✅ Vitest + Testing Library · ✅ Prettier + ESLint (hard comment gate) + lefthook · ✅ Docker (Nginx)

### FastAPI
✅ FastAPI + Uvicorn + Pydantic v2 · ✅ structlog JSON logging · ✅ Ruff + Pyright  
✅ pytest + httpx (async) · ✅ Docker

### NestJS
✅ NestJS + Fastify · ✅ Swagger docs · ✅ nestjs-pino + nestjs-zod · ✅ Vitest + e2e tests  
✅ Prettier + ESLint (hard comment gate) + lefthook · ✅ Docker

> Add capabilities via `templatecentral:add` — `auth · database · page · feature · endpoint · form · integration · test · logging · error-handling · pagination · mutation-testing · ai-security · documentation · redaction` — keeping the base scaffold clean.

---

## What Makes It Different

The value is in the details an ordinary setup gets wrong. Most rows began as a failure found in real use.

| Detail | What templatecentral does | Why it matters |
|:---|:---|:---|
| Branch guard reads the right folder | `block-no-verify.sh` judges a commit by the folder it actually runs in — the hook input's `cwd` plus each literal `cd` in a strict `&&` chain. Anything it cannot resolve also checks the project root. | In a worktree, a naive guard reads the main checkout's branch: it blocks every legitimate commit or misses a commit to `main`. |
| Every bypass spelling is closed | Blocks `--no-verify`, `-n`, `HUSKY=0`, `LEFTHOOK=0`, `git -c core.hooksPath=…`, `git config core.hooksPath`, force-push or delete of protected branches (incl. `+refspec`, `HEAD:main`), and checkout/restore of guard files. Heredoc commit-message text is ignored. | Blocking only `--no-verify` leaves five other ways around the hooks, and an agent will find one. |
| Secrets blocked, governance asked | `protect-files.sh` hard-blocks `.env*`, `secrets/` and cert files, and asks a human before edits to `AGENTS.md`, the constitution, hooks, settings, CI and the audit allowlist. Paths are canonicalised, so `src/../.github/…` or a symlink cannot disguise the target. | A hard block on CI files also blocks the approved edit; an ask keeps a human in the loop without stopping the work. |
| Tamper detection | `verify-harness.sh` recomputes every enforcement file's hash against `.claude/harness.json` on pre-push and in CI. | If the agent edits a hook to get past it, the next push or PR fails. |
| Upgrades keep local rules | `.claude/.harness-base/` stores the last-seeded bytes, so `migrate` does a three-way re-sync. Project rules in `.claude/hooks/local/` are never touched. | Take upstream security fixes without losing your own guards. |
| Gates fail closed | CI gates fail when a tool is missing, the base branch is missing, output cannot be parsed, or an audit covered nothing. | A gate that passes when it cannot run is no gate. |
| Dependency audit with no bypass | Audits every `pnpm-lock.yaml`, `uv.lock` and `requirements*.txt` for high/critical advisories. Exceptions live only in `.claude/dep-audit-allow.txt` with a reason and an expiry at most 180 days out; package-manager ignore lists are rejected. | Suppressions cannot pile up silently or hide where the gate cannot see them. |
| Authorization denies by default | `add auth` ships role and ownership helpers per stack (`require_roles` / `ensure_owner`, `@Roles` + `RolesGuard` / `assertOwner`, `hasRole` / `isOwner`) with tests. Roles come from the database, never the token; another user's record returns 404. | Revoking a role takes effect on the next request, and record ids cannot be probed. |
| Done means tests pass | The `Stop` hook runs the test suite and `SubagentStop` runs the type check; a failure sends the agent back to fix it. | "Done" is checked, not claimed. |
| Same rules on any host | One `ci-gates.sh` serves GitHub Actions and Azure Pipelines; pipelines that already run a check are reused, not duplicated. | No dead pipeline files, one source of truth for reviewers. |
| Keeps enforcing without the plugin | The guards are files in your repo, not part of the plugin. | Uninstalling the plugin does not switch the rules off. |

## Ordinary Harness vs templatecentral

An ordinary harness writes the rules down. templatecentral enforces them, checks the enforcement itself, and keeps it current.

| Area | Ordinary harness | templatecentral |
|:---|:---|:---|
| Rules | `CLAUDE.md` the agent may ignore | Hooks that block, plus a constitution re-injected after compaction |
| Hook bypass | Usually only `--no-verify` | All known bypass spellings, judged by the folder the command runs in |
| Hook tampering | Agent can edit the hook | Edits ask a human; hash drift fails push and CI |
| Secrets | `.gitignore` | Writes hard-blocked; reads denied in `permissions.deny` |
| Done check | The agent's word | Tests on `Stop`, types on `SubagentStop` |
| Dependency audit | Optional, skippable by label | Blocking, every ecosystem, expiring allowlist only |
| Authorization | Left to each developer | Deny-by-default helpers with tests, 404 on ownership |
| Upgrades | Copy and paste, local edits lost | Three-way re-sync; local guards kept |
| CI host | One host per setup | GitHub Actions and Azure Pipelines from one script |
| Setup time | ~45 minutes of decisions | ~60 seconds from one prompt |

## Proof, Not Promises

| Evidence | Result |
|:---|:---|
| Harness kit regression suite (`scripts/test-harness-kit.sh`) | 721 tests pass |
| OpenCode adapter hook matrix | 157 tests pass |
| Repo guard tests (`scripts/pre-guard.test.sh`) | 67 tests pass |
| Branch-guard rewrite | Checked against the previous hook over 248 command × folder combinations; nothing it blocked became allowed |
| End-to-end sweeps | A real project per stack, built from the skill files: install, format, lint, typecheck, tests with coverage, harness and hook checks all pass |
| Dependency audit with real tools | pnpm, pip-audit and uv: clean scaffolds pass; a known advisory such as `lodash: GHSA-35jh-r3h4-6jhm (high)` fails and is named |
| Real databases | PostgreSQL 18.3 and MongoDB 8.2 — caught that 20 concurrent duplicate sign-ups all succeeded on a fresh Mongo database; now 1 of 20 is stored |

Running the scaffolds, not reading them, has surfaced more than 20 defects — anonymous access to `GET /users`, a database connection without TLS, a password hash blocking the event loop — each fixed in the skills. See [CHANGELOG.md](CHANGELOG.md).

---

## Available Skills (8)

**User-invocable (4):**

| Skill | What it does |
|-------|-------------|
| `templatecentral:scaffold` | Scaffold a new Next.js, Vite+React, FastAPI, or NestJS project from scratch |
| `templatecentral:add` | Add any capability to an existing project — auth, database, tests, components, pages, API routes, forms, logging, error handling, pagination, integrations, and more |
| `templatecentral:standards` | Review code quality, naming conventions, validation patterns, drift, and full-stack type contracts |
| `templatecentral:migrate` | **Adopt/retrofit the harness** into a project built without templateCentral, upgrade a project to current conventions, switch the DB access layer (Drizzle → Kysely, SQLAlchemy → AWS IAM auth), or extract a Next.js backend into NestJS/FastAPI |

**Agent utilities (4)** — loaded internally by agents, not invoked directly by users:

| Skill | What it does |
|-------|-------------|
| `build` | Detect stack, run the build command, report failures without auto-fixing |
| `test` | Write tests for newly added code and run the full test suite |
| `review` | Analyse code quality and flag issues, or bump dependencies (patch/minor, rollback on failure, majors reported) |
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

## Other Agent Tools (OpenCode, Codex, Antigravity)

Claude Code is the primary target, but the skills follow the open [Agent Skills](https://agentskills.io) and [`AGENTS.md`](https://agents.md) standards, so they run in any compliant tool. You get the full scaffold logic and routing — only the Claude-Code-only in-agent hooks differ (and those stay enforced at commit/CI time).

**Prerequisite — clone the repo and generate a tool-agnostic copy.** Other tools require each skill's `name` to match its folder, so this strips the `templatecentral:` namespace:

```bash
git clone https://github.com/cljiahao/templatecentral.git
cd templatecentral
bash scripts/build-agents-dist.sh        # → dist/agents-skills/
```

### OpenCode / OpenChamber

1. **Register the skills** — add to `opencode.json` (project `./opencode.json` or global `~/.config/opencode/opencode.json`):

   ```json
   {
     "$schema": "https://opencode.ai/config.json",
     "skills": { "paths": ["/abs/path/to/templatecentral/dist/agents-skills"] }
   }
   ```

2. **(Optional) Add the live guards** — block `git --no-verify`, protect `.env`/secrets, typecheck-on-edit:

   ```json
   { "plugin": ["/abs/path/to/templatecentral/adapters/opencode/templatecentral.plugin.js"] }
   ```

3. **Restart OpenCode** — it loads config only at startup.

Verify: ask *"scaffold a Next.js project at ./my-app"* — OpenCode auto-activates the `scaffold` skill.

> **OpenChamber / Docker:** instead of step 1, mount `dist/agents-skills` to `/home/developer/.config/opencode/skills` and restart the container.

### Codex / Antigravity

Both read `AGENTS.md` natively. Copy the skills into their scan path, then restart:

```bash
cp -R dist/agents-skills/* ~/.agents/skills/     # Codex   (or a project ./.agents/skills/)
cp -R dist/agents-skills/* .agents/skills/       # Antigravity (project-local)
```

---

📖 **Full reference:** [`docs/CROSS-TOOL.md`](docs/CROSS-TOOL.md) — every skill-path option, the guard-parity table, and the per-tool adapter roadmap.

---

## Scheduled Loops

- **`scaffold-verify`** (monthly) — scaffolds a test project from each template and runs its build + test gate, catching regressions before they reach users.
- **`ecosystem-refresh`** (paused) — re-scans framework release notes, library changelogs and security advisories, then opens a PR updating `.claude/audit-ecosystem-research.md`. The research agent runs read-only with no shell; a separate job with no AI in it validates the output and opens the PR. While paused, maintainers refresh the research file by hand, and `/tc-audit` re-scans when it is more than 30 days old.

Both need an `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` repository secret (they skip cleanly without one). See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Repository Structure

```
templatecentral/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (points to skills/)
│   └── marketplace.json     # Marketplace manifest (`claude plugin marketplace add`)
├── .github/workflows/       # CI — skill lint + manifest, scaffold parse/verify, AI review, ecosystem refresh, dist build, release
├── scripts/
│   ├── lint-skills.sh       # Mechanical pattern checks for all skill files
│   ├── validate-manifest.sh # Validates plugin.json + marketplace.json before publish
│   ├── validate-scaffold-configs.sh # Parses fenced JSON/JS config blocks in scaffold files
│   ├── test-harness-kit.sh  # Regression suite for the hooks the harness kit (harness-kit*.md) seeds
│   ├── build-agents-dist.sh # Builds the namespace-free copy for other agent tools
│   ├── pre-guard.sh         # Repo guard: blocks secret access, asks before instruction/CI edits
│   ├── bash-guard.sh        # Repo guard: blocks shell reads/writes of secret files
│   ├── post-edit-lint.sh    # Repo hook: lint feedback after skill edits
│   └── pre-guard.test.sh    # Tests for both repo guards
├── skills/                  # Shipped skills — nested reference file architecture
│   ├── CONVENTIONS.md       # Single source of truth for skill authoring rules
│   ├── scaffold/SKILL.md    # Router → skills/scaffold/<stack>/
│   ├── add/SKILL.md         # Router → skills/add/<capability>/<stack>.md
│   ├── standards/SKILL.md   # Router → skills/standards/<check>/
│   ├── migrate/SKILL.md     # Router → skills/migrate/<type>/
│   ├── build/               # (de-registered utility) detect stack + run build command
│   ├── test/                # (de-registered utility) write and run tests
│   ├── review/              # (de-registered utility) code review + dependency updates
│   └── cleanup/             # (de-registered utility) remove example code / task scaffolding
├── adapters/opencode/       # OpenCode plugin porting the in-agent guards
├── docs/CROSS-TOOL.md       # Running the skills outside Claude Code
├── .claude/skills/          # Repo-internal contributor skills (NOT shipped to installs)
│   ├── tc-audit/            # /tc-audit — full ecosystem + accuracy audit
│   └── tc-write-skill/      # /tc-write-skill — skill authoring checklist
├── AGENTS.md                # Agent orchestration guide
└── CHANGELOG.md             # Full version history
```

---

## Adding a New Skill

Contributions welcome — especially new stacks and coverage gaps.

1. Read `skills/CONVENTIONS.md` — it defines all nesting rules, description limits, and ref header formats
2. Use `/tc-write-skill` — it walks through the authoring checklist and validates your skill before you open a PR
3. If adding a new stack, create `.claude/rules/<stack>.md`
4. Run `bash scripts/lint-skills.sh skills/` and `bash scripts/validate-manifest.sh` locally — both must pass
5. Open a PR — CI will run both scripts automatically

> **Contributor-only skills.** `/tc-write-skill` (authoring) and `/tc-audit` (full ecosystem + accuracy audit) live in this repo under `.claude/skills/` and are available as project skills when you clone and open the repo. They are **not** shipped to installed projects — end users never carry the plugin's maintenance tooling.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

---

## ⭐ Star This Repo

If templatecentral saves you setup time, a star helps others find it.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=cljiahao/templatecentral&type=Date)](https://star-history.com/#cljiahao/templatecentral&Date)

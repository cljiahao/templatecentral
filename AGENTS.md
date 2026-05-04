# AGENTS.md — templateCentral

templateCentral is a plugin of production-ready scaffolding skills for creating new applications. It is NOT an application itself.

## Task Routing

Detect the stack from project files or user request (`next.config.ts/js/mjs` → nextjs, `requirements.txt` with fastapi → fastapi, `vite.config.ts/js` → vite-react, `nest-cli.json` or `@nestjs/core` in `package.json` → nestjs). If ambiguous, ask. Meta-tasks (auditing templateCentral itself) stay with the orchestrator.

### New project → scaffold skill

| User wants | Skill |
|------------|-------|
| New Next.js app | `nextjs-scaffold` |
| New FastAPI backend | `fastapi-scaffold` |
| New Vite + React SPA | `vite-react-scaffold` |
| New NestJS API | `nestjs-scaffold` |

### Existing project → add-* skill

| Task | Next.js | FastAPI | NestJS | Vite+React |
|------|---------|---------|--------|-----------|
| Authentication & login | `nextjs-add-auth` | `fastapi-add-auth` | `nestjs-add-auth` | `vite-react-add-auth` |
| Database | `nextjs-add-database` | `fastapi-add-database` | `nestjs-add-database` | — |
| Page / screen | `nextjs-add-page` | — | — | `vite-react-add-page` |
| Feature module | `nextjs-add-feature` | — | `nestjs-add-module` | `vite-react-add-feature` |
| API route / endpoint | `nextjs-add-api-route` | `fastapi-add-endpoint` | — | — |
| UI component | `nextjs-add-component` | — | — | `vite-react-add-component` |
| Form | `nextjs-add-form` | — | — | `vite-react-add-form` |
| External integration | `nextjs-add-integration` | `fastapi-add-integration` | `nestjs-add-integration` | `vite-react-add-integration` |
| Tests | `nextjs-add-test` | `fastapi-add-test` | `nestjs-add-test` | `vite-react-add-test` |
| Code standards review | `nextjs-code-standards` | `fastapi-code-standards` | `nestjs-code-standards` | `vite-react-code-standards` |

### Cross-stack tasks → shared-* skill

| Task | Skill |
|------|-------|
| Confirm project builds clean | `shared-build-agent` |
| Write and run tests for new code | `shared-test-agent` |
| Review code against standards | `shared-review-agent` |
| Update dependencies | `shared-update-agent` |
| Check convention/dep freshness (session start) | `shared-drift-check` |
| Add structured JSON logging | `shared-add-logging` |
| Add consistent error handling | `shared-add-error-handling` |
| Add input validation (forms, APIs, uploads) | `shared-validation-patterns` |
| Add pagination | `shared-add-pagination` |
| Connect frontend to backend | `shared-full-stack-pairing` |
| Remove template example code | `shared-remove-example` |
| Plan complex multi-step features | `shared-task-management` |

## Scaffolding flow (order matters)

1. Confirm stack → use the `<stack>-scaffold` skill.
2. Generate all project files from verbatim blocks per skill; configure name/metadata; env **only** from `.env.example` / `.env.default` (no real secrets).
3. Install deps per scaffold (**Node**: default **`pnpm`**, `corepack enable` if needed; **Python**: venv then activate — Windows `.venv\Scripts\activate`, Unix `source .venv/bin/activate`); run **Scaffold verification** gates; fix failures before project docs.
4. Write the **new project’s** `AGENTS.md`, then `CLAUDE.md` if Claude Code — never before gates pass. If they use git: **`git init`**, first commit should include the **lockfile**, never `.env` / `.env.local` with real secrets.
5. Post-scaffold code changes: read the project’s `AGENTS.md` and stack **`code-standards/`** first. After non-trivial work, consider **Independent test workflow** (Tier 1) — a fresh session focused on tests only.

### What to add after scaffolding

If the user’s request included specific feature requirements, invoke the corresponding skill immediately after verification gates pass:

| User wants | First skill | Then |
|------------|-------------|------|
| Auth only | `<stack>-add-auth` | — |
| Database only | `<stack>-add-database` | — |
| Auth + database | `<stack>-add-auth` first, then `<stack>-add-database` | Order matters — database skill completes the auth stub |
| Logging | `shared-add-logging` | — |
| Error handling | `shared-add-error-handling` | — |

**Auth + database ordering**: `fastapi-add-auth` and `nestjs-add-auth` create a stub `AuthService` that raises 501/`NOT_IMPLEMENTED` until a database is wired. Always run `add-auth` before `add-database` when both are requested — the database skill’s "Completing Auth Integration" section activates the stub with real DB calls. Running them in the wrong order means the integration section has no stub to complete.

## Code Quality (applies to every agent writing code)

These rules are not optional. Every subagent writing or modifying code must follow them before marking a task done.

- **YAGNI.** Write only what the current task requires. No extra methods, helpers, abstractions, or files "that might be useful later." Future tasks will add what they need.
- **DRY.** Don't duplicate logic. If the same logic appears in two places, extract it. If it appears once, inline it — don't extract prematurely.
- **SRP.** Every file, function, and module does one thing. A route handler handles HTTP; a service handles business logic; a repository handles data access. Never mix layers.
- **SoC.** Keep concerns separate at every level — UI from data fetching, validation from business logic, config from implementation. A change in one layer must not force changes in another.
- **No premature abstractions.** Two similar things is a coincidence. Three is a pattern worth extracting. Don't abstract until the third callsite exists.
- **No dead code.** Don't leave commented-out code, unused imports, unused variables, or TODO stubs.
- **No tech debt shortcuts.** Don't write `// fix later`, `// temp`, or workarounds that leave the codebase worse than you found it.
- **Validate at every boundary.** User input, API responses, env vars, file uploads — always validate with Zod (TS) or Pydantic (Python). Never trust external data.
- **Fail loudly, not silently.** Don't swallow errors with empty catch blocks. Log with context; return meaningful status codes.
- **Least privilege.** Return only the fields the caller needs. Never send full DB records to the browser. Never expose internal IDs without auth checks.
- **No secrets in code.** No hardcoded tokens, passwords, connection strings, or API keys — ever. Use env vars; document them in `.env.example`.

## Backend testing policy

Stacks with a backend (**FastAPI**, **NestJS**, **Next.js** server/API code) **MUST** include automated tests for new or changed backend behavior in the same change as the code:

- **FastAPI** — pytest for routers, services, and domain logic (`test/`).
- **NestJS** — Jest for controllers, services, and repositories (`test/`); e2e where the skill prescribes it.
- **Next.js** — Vitest for `src/app/api/**` and server-only logic they call (`test/api/`). **No** requirement to add tests for React components, pages, or client hooks.

Subagents read their stack’s `code-standards` skill before writing code; those standards include this rule. **Vite + React** is out of scope for this policy (frontend template only).

## Independent test workflow (recommended for AI sessions)

Backend tests must still land in the **same change / PR** as the feature (**Backend testing policy** above). The tiers below are about **who runs which chat or agent session** to reduce shared blind spots — not about deferring tests to a later PR.

| Tier | When | What to do |
|------|------|------------|
| **0 — Default** | Any implementation | Author adds tests in the same session; run **Scaffold verification** or project test/build commands. Often enough for small edits. |
| **1 — Test author (new session)** | After scaffold or a non-trivial feature | Start a **fresh** agent/chat. Role: *you did not write the production code* — read the project `AGENTS.md`, stack **`add-test/`** and **`code-standards/`**, then add or strengthen tests (error/edge paths and assertions appropriate to the stack: API status/validation, services, or UI per skill). Merge into the same branch before merge. |
| **2 — Test reviewer (another new session)** | **Selective** — auth, security-sensitive paths, payments, complex business rules, or pre-release hardening | Another fresh session reviews **only** the test files: missing cases, assertions that cannot fail, gaps vs stated behavior. **Not** required for every PR — use judgment to save time and tokens. |
| **Cheap check** | Always | **CI** runs the suite; fix failures. Prefer this over a third LLM when coverage is straightforward. |

**Token / cost note**: Tier 1 is a strong default for templateCentral-backed work. Tier 2 is **optional** quality insurance, not a mandatory third pass on every change.

## Security & secrets

- **Never** commit real secrets, production `.env` contents, or API keys. Scaffold and templates use `.env.example` / `.env.default` only; users or CI inject secrets at runtime.
- **Never** paste live credentials into `AGENTS.md`, `CLAUDE.md`, generated docs, or chat output. Rotate any secret that was exposed.
- **Never** commit private keys, `.pem` files, or SSH keys — if the project needs them locally, keep them out of git (`.gitignore`) and out of generated docs.
- **Never** put secrets in `NEXT_PUBLIC_*` (Next.js) or `VITE_*` (Vite) — both are exposed in the client bundle.
- **Next.js**: Always keep `next` on a current version — critical security patches release regularly. Minimum safe: **16.2.4+** or **15.5.9+** (15.x). Run `shared-update-agent` to keep it current.
- **FastAPI**: In development, CORS allows `localhost:3000`, `localhost:5173`, and `127.0.0.1` variants automatically. In production, set `CORS_ORIGINS` env var (comma-separated) to your frontend's domain.
- **Production**: Replace template dev placeholders in env (e.g. better-auth `BETTER_AUTH_SECRET`, JWT secrets) with strong values before deploy — call this out in handoff when templates use placeholders.
- Follow each stack’s `code-standards` for auth, env vars, and least-privilege responses.

## Supply chain & reproducibility

- **Node projects**: Use the package manager the scaffold documents (**pnpm** for current templates); after first `pnpm install`, **commit the new lockfile**. Do not delete lockfiles or switch npm/pnpm/yarn without explicit user approval.
- **pnpm version**: Ensure the `"packageManager"` field in scaffolded `package.json` targets **pnpm ≥10.33.2**; run `pnpm --version` to verify before first install.
- **Python projects**: Install from the template’s `requirements-dev.txt` (or equivalent); do not loosen version pins without user approval.

## Scaffold verification (before project AGENTS.md / CLAUDE.md)

Do not write `AGENTS.md` or `CLAUDE.md` until the stack’s checks pass (fixes first):

| Stack | Required gates |
|-------|------------------|
| **Next.js** | `pnpm test`, `pnpm build`, `pnpm check` |
| **NestJS** | `pnpm test`, `pnpm test:e2e`, `pnpm build` |
| **FastAPI** | API responds, `pytest test/`, `ruff check src/` |
| **Vite + React** | `pnpm dev` OK, `pnpm test`, `pnpm build`, `pnpm check` |

## Subagent Boundaries

- NEVER invent APIs, libraries, or features not in the stack
- NEVER modify files outside the project directory
- NEVER commit, push, or deploy without explicit user instruction
- NEVER delete user code without confirmation
- NEVER remove or ignore lockfiles in scaffolded Node projects without explicit user approval
- NEVER scaffold into a **non-empty** target directory without explicit user confirmation (avoid overwriting existing apps)
- NEVER disable TLS verification in application code, HTTP clients, or scaffold scripts (`verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, etc.) unless the user explicitly approves a **narrow, documented dev-only** exception

## Scaffold: optional Task Management (single source of truth)

Ask whether the user wants structured task management. If **yes**, append **one** of the blocks below to the **new project’s** `AGENTS.md`. If **no**, skip.

**Option A — templateCentral protocol** (no plugin):

```markdown
## Task Management

For complex tasks (3+ files, architectural decisions), use the `shared-task-management` skill. Protocol: Plan → Verify → Track → Explain → Document → Capture Lessons. Skip for single-file edits or quick fixes.
```

**Option B — Superpowers** (Claude Code plugin — already installed if you're using Claude Code with this plugin):

Append to the project's `AGENTS.md`:

```markdown
## Task Management

- **Simple tasks**: use templateCentral skills for this stack
- **Complex features** (3+ files, architectural decisions): `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan` (verify slash command syntax for your installed superpowers version)
- All code must follow this file’s conventions and the stack’s code-standards
```

## Project Memory Requirement

Every scaffolded project **MUST** get its own `AGENTS.md` at the root — scaffolding is not complete without it. Records stack, template source, architecture decisions, and a "Project-Specific Notes" section. Read it first on every session; append significant decisions as they happen.

For **Claude Code users**, also generate a `CLAUDE.md` (see below). Both coexist — `AGENTS.md` is the source of truth; `CLAUDE.md` is a short index, not a duplicate.

## Recommended plugins for new projects

**caveman**, **claude-mem**, and **superpowers** are installed by default in the post-scaffold step (each scaffold skill handles this for Claude Code users). Growth-stage plugins are opt-in — suggest them as the project matures.

**Installed by default (all stacks, Claude Code users only):**
- **caveman** (`claude plugin marketplace add JuliusBrussee/caveman`) — compresses output prose. **OFF** in sessions writing committed files (`SKILL.md`, `AGENTS.md`, `CLAUDE.md`, docs).
- **claude-mem** (`claude plugin marketplace add thedotmack/claude-mem` then `claude plugin install claude-mem`) — auto-captures tool usage, decisions, and file changes across sessions via SQLite + vector DB. Installed in the **scaffolded project**, not templateCentral (templateCentral uses built-in markdown memory instead).
- **superpowers** (`claude plugin marketplace add obra/superpowers`) — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**As the project grows (5+ features):**
- **codegraph** (`npx @colbymchenry/codegraph`, Node 22+) — symbol navigation; add when grepping for definitions is a regular cost.
- **graphify** (`uv tool install graphifyy && graphify install`, Python 3.10+) — structural overview; use before codegraph for orientation.
- **code-review-graph** (`pip install code-review-graph && code-review-graph install && code-review-graph build`, Python 3.10+) — PR/refactor impact analysis; add when blast radius is non-obvious.

Full decision rules: `README.md → Recommended Plugins`.

## Scaffold: CLAUDE.md (Claude Code only)

Skip if the user does not use Claude Code. Add after `AGENTS.md` and after verification gates pass.

- **Never** duplicate `AGENTS.md` content — one line: "Full context in `AGENTS.md`."
- **Include**: verified Build & Dev commands; templateCentral skills list for this stack (e.g. `<stack>-scaffold`, `<stack>-add-auth`); workflow line: simple/medium → templateCentral skills; complex → Superpowers.
- **Never** put secrets or env values in `CLAUDE.md`.

If templateCentral is not on disk, write `AGENTS.md` and a minimal `CLAUDE.md` from verified commands and local content.

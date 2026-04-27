# Plugin-First Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate templateCentral from MCP-server + 3-skill plugin to a fully self-contained plugin with all 46 skills, eliminating `templates/` and `mcp-server/` entirely so users get everything by installing the plugin with no repo cloning required.

**Architecture:** Each scaffold skill becomes the single source of truth for its stack — it generates every project file from verbatim inline blocks and precise generation rules, with no dependency on file copying from `templates/`. Package installs use no version pins so Claude resolves the latest compatible versions at scaffold time. The `skills/` flat directory (`<stack>-<skill>` naming) replaces both `claude-skills/` (MCP source tree) and the existing 3-skill partial plugin, eliminating the dual-copy maintenance problem.

**Tech Stack:** Claude Code plugin format, Markdown skill files, pnpm (Next.js/NestJS/Vite-React), pip/pyproject.toml (FastAPI), TypeScript 6 / Next.js 16 / NestJS / Vite 6 / FastAPI 0.116+

**Priority:** Accuracy and security first (verbatim blocks, no hallucinated imports, correct Dockerfiles, safe error handling). Token reduction second (verbatim reduces retry loops; concise generation rules reduce prompt re-reads).

---

## File Map

**Deleted at end of migration:**
- `claude-skills/` — entire directory (content migrated to `skills/`)
- `templates/` — entire directory (content encoded in scaffold skills as verbatim blocks)
- `mcp-server/` — entire directory
- `.mcp.json` — no longer needed

**Modified:**
- `skills/` — grows from 3 → 46 flat skill directories
- `.claude-plugin/plugin.json` — updated with full skill list and version bump
- `.claude-plugin/marketplace.json` — updated description
- `.claude/rules/*.md` — remove stale `claude-skills/` and `templates/` path references
- `AGENTS.md` (root) — updated architecture description
- `README.md` — updated usage instructions
- `.gitignore` — remove mcp-server/dist entry if present

**New files:**
- `docs/superpowers/plans/2026-04-27-plugin-first-migration.md` (this file)

---

## Scaffold Skill Verbatim Standard

Every scaffold skill must follow this standard. This is the contract that makes plugin-only reliable.

### File classification

| Class | Tag | Criteria |
|-------|-----|----------|
| Config | `[verbatim]` | Short, exact, rarely changes: tsconfig, eslint, prettier, next.config, postcss, vitest, pyproject.toml, nest-cli.json, vite.config |
| Security-critical | `[verbatim]` | Files whose mistakes cause vulnerabilities: Dockerfile, docker-entrypoint.sh, .gitignore, .env.example, error handlers, API route handlers, auth config |
| Infrastructure | `[verbatim]` | Files where exact content matters for correctness: providers.tsx, layout.tsx, lib/errors/*, core/config.py, core/exceptions.py, app.py/main.py |
| Boilerplate | `[generate]` | Files where structure matters but exact content is flexible: README.md, AGENTS.md, navbar, footer, example feature |
| User-customised | `[generate]` | Files user immediately edits: routes.ts, branding components |

### Package version policy

**Never pin versions in skill package lists.** The skill lists package names; Claude resolves latest at install time.

- Node/pnpm: `pnpm add react next react-dom` (no `@version`)
- Python: `pip install fastapi uvicorn pydantic pydantic-settings` (no `==version`)
- After install: run the project's typecheck/lint/test suite as the verification gate — if it fails, the package resolved to a breaking version; fix then.
- The installed versions get captured in the project's lockfile (`pnpm-lock.yaml`, `requirements.txt` via `pip freeze`) — that's reproducibility for the scaffolded project, not the skill.

### AGENTS.md generation rule (applies to all scaffold skills)

Each scaffold skill generates a project-level `AGENTS.md` containing:
1. `<!-- templateCentral: <stack>@<date> -->` version comment on line 1
2. Project name, stack, scaffold date
3. Architecture decisions (copy from the skill's own architecture section — don't summarise)
4. Stack-specific conventions (copy from the skill's conventions section)
5. "Skills available" table listing all `<stack>-*` skill names
6. A blank "Project-specific notes" section

---

## Task 1: Flatten claude-skills/ into skills/ (single source of truth)

**Goal:** Create all 46 skills as flat directories under `skills/<stack>-<skill>/SKILL.md`, then delete `claude-skills/` entirely, leaving `skills/` as the only skill store.

**Files:**
- Create: `skills/fastapi-scaffold/SKILL.md` through `skills/vite-react-add-test/SKILL.md` (43 new files — full list in Steps)
- Delete: `claude-skills/` (entire directory)
- Modify: `skills/nextjs-scaffold/SKILL.md`, `skills/nextjs-add-auth/SKILL.md`, `skills/nextjs-add-page/SKILL.md` (verify identical to claude-skills source before delete)

**Acceptance Criteria:**
- [ ] `skills/` contains exactly 46 directories, each with a `SKILL.md`
- [ ] `claude-skills/` directory is gone from the repo
- [ ] `git diff HEAD` shows zero content changes to skill text (only location changes)
- [ ] `skills/nextjs-scaffold/SKILL.md` is identical to what `claude-skills/nextjs/scaffold/SKILL.md` was

**Verify:** `find skills -name SKILL.md | wc -l` → `46`

**Steps:**

- [ ] **Step 1: Confirm the 3 existing skills/ copies match claude-skills/ source**

```bash
diff skills/nextjs-scaffold/SKILL.md claude-skills/nextjs/scaffold/SKILL.md
diff skills/nextjs-add-auth/SKILL.md claude-skills/nextjs/add-auth/SKILL.md
diff skills/nextjs-add-page/SKILL.md claude-skills/nextjs/add-page/SKILL.md
```

Expected: zero diff output. If diff shows differences, the claude-skills/ version is authoritative — overwrite the skills/ copy before proceeding.

- [ ] **Step 2: Copy all remaining skills to skills/ using the mapping below**

Mapping table (`claude-skills/<stack>/<skill>/` → `skills/<stack>-<skill>/`):

```
fastapi/add-auth        → fastapi-add-auth
fastapi/add-database    → fastapi-add-database
fastapi/add-endpoint    → fastapi-add-endpoint
fastapi/add-integration → fastapi-add-integration
fastapi/add-test        → fastapi-add-test
fastapi/code-standards  → fastapi-code-standards
fastapi/scaffold        → fastapi-scaffold

nestjs/add-auth         → nestjs-add-auth
nestjs/add-database     → nestjs-add-database
nestjs/add-integration  → nestjs-add-integration
nestjs/add-module       → nestjs-add-module
nestjs/add-test         → nestjs-add-test
nestjs/code-standards   → nestjs-code-standards
nestjs/scaffold         → nestjs-scaffold

nextjs/add-api-route    → nextjs-add-api-route
nextjs/add-component    → nextjs-add-component
nextjs/add-database     → nextjs-add-database
nextjs/add-feature      → nextjs-add-feature
nextjs/add-form         → nextjs-add-form
nextjs/add-integration  → nextjs-add-integration
nextjs/add-test         → nextjs-add-test
nextjs/code-standards   → nextjs-code-standards

vite-react/add-auth         → vite-react-add-auth
vite-react/add-component    → vite-react-add-component
vite-react/add-feature      → vite-react-add-feature
vite-react/add-form         → vite-react-add-form
vite-react/add-integration  → vite-react-add-integration
vite-react/add-page         → vite-react-add-page
vite-react/add-test         → vite-react-add-test
vite-react/code-standards   → vite-react-code-standards
vite-react/scaffold         → vite-react-scaffold

shared/add-error-handling  → shared-add-error-handling
shared/add-logging         → shared-add-logging
shared/add-pagination      → shared-add-pagination
shared/build-agent         → shared-build-agent
shared/drift-check         → shared-drift-check
shared/full-stack-pairing  → shared-full-stack-pairing
shared/remove-example      → shared-remove-example
shared/review-agent        → shared-review-agent
shared/task-management     → shared-task-management
shared/test-agent          → shared-test-agent
shared/update-agent        → shared-update-agent
shared/validation-patterns → shared-validation-patterns
```

Use a shell loop to copy:

```bash
cd /path/to/templateCentral

# Example pattern — repeat for each mapping above
mkdir -p skills/fastapi-add-auth
cp claude-skills/fastapi/add-auth/SKILL.md skills/fastapi-add-auth/SKILL.md
# ... repeat for all 43 new entries
```

- [ ] **Step 3: Verify count**

```bash
find skills -name SKILL.md | wc -l
```

Expected: `46`

- [ ] **Step 4: Delete claude-skills/**

```bash
git rm -r claude-skills/
```

- [ ] **Step 5: Commit**

```bash
git add skills/
git commit -m "refactor: flatten claude-skills/ into skills/ (plugin-first migration step 1)"
```

---

## Task 2: Update cross-references inside all skills

**Goal:** Remove every reference to `claude-skills/` paths and `templates/` paths inside skill files, replacing them with plugin-style `<stack>-<skill>` references.

**Files:**
- Modify: any `skills/*/SKILL.md` containing `claude-skills/` or `templates/` path strings
- Modify: `.claude/rules/fastapi.md`, `.claude/rules/nestjs.md`, `.claude/rules/nextjs.md`, `.claude/rules/vite-react.md` (remove any `templates/` references)
- Modify: `AGENTS.md` (root) — remove MCP and `claude-skills/` references

**Acceptance Criteria:**
- [ ] `grep -r "claude-skills/" skills/` returns zero results
- [ ] `grep -r "templates/" skills/` returns zero results (except inside verbatim Dockerfile COPY instructions — those refer to the Docker build context, not this repo)
- [ ] All skill-to-skill references use the form `<stack>-<skill>` (e.g. `shared-remove-example`, `nextjs-add-auth`)

**Verify:** `grep -r "claude-skills/\|templates/" skills/ | grep -v "COPY\|ADD\|FROM"` → zero output

**Steps:**

- [ ] **Step 1: Find all references to replace**

```bash
grep -rn "claude-skills/" skills/ --include="*.md"
grep -rn "templates/" skills/ --include="*.md" | grep -v "COPY\|ADD\|FROM"
```

Record every file and line. Common patterns to fix:

| Old reference | New reference |
|---------------|---------------|
| `claude-skills/fastapi/` | `fastapi-` skills (no path) |
| `claude-skills/shared/remove-example/SKILL.md` | `shared-remove-example` skill |
| `templates/fastapi/` | _(remove — scaffold skill generates files directly)_ |
| `<repo-root>/templates/nestjs/` | _(remove)_ |
| `rsync -av ... <repo-root>/templates/...` | _(remove — replaced in Task 4-6)_ |
| `Scaffolded from: templateCentral/templates/fastapi` | `Scaffolded via templateCentral fastapi-scaffold skill` |

- [ ] **Step 2: Apply replacements file by file**

For each file identified in Step 1, make the targeted edits. Do not change any skill logic — only change path strings and references.

Key files that need edits (based on grep output from current state):
- `skills/fastapi-scaffold/SKILL.md` — multiple `templates/fastapi/` and `claude-skills/` refs
- `skills/fastapi-add-*/SKILL.md` — `claude-skills/shared/` refs
- `skills/nestjs-scaffold/SKILL.md` — `templates/nestjs/` refs
- `skills/vite-react-scaffold/SKILL.md` — `templates/vite-react/` refs
- `skills/shared-remove-example/SKILL.md` — may reference `templates/` structure

- [ ] **Step 3: Update .claude/rules/ files**

In each `.claude/rules/<stack>.md`, find any `templates/` references (e.g. "Scaffold new X projects from `templates/X/`") and replace with "Scaffold new X projects using the `<stack>-scaffold` skill".

- [ ] **Step 4: Update root AGENTS.md**

In `AGENTS.md` at the repo root, update the architecture description to say:
- Skills live in `skills/` (flat, `<stack>-<skill>` naming)
- No `templates/` directory — scaffold skills generate all files verbatim
- No MCP server — distribution is via plugin only

- [ ] **Step 5: Commit**

```bash
git add skills/ .claude/rules/ AGENTS.md
git commit -m "refactor: remove claude-skills/ and templates/ path refs from all skills"
```

---

## Task 3: Rewrite NextJS scaffold — promote [generate] to [verbatim] for accuracy-critical files

**Goal:** Convert all security-critical and infrastructure [generate] files in `skills/nextjs-scaffold/SKILL.md` to [verbatim] blocks, and remove all version pins from the package install list.

**Files:**
- Modify: `skills/nextjs-scaffold/SKILL.md`

**Acceptance Criteria:**
- [ ] `layout.tsx` is [verbatim] (currently [generate] — risk of Toaster being added back)
- [ ] `src/app/api/route.ts` and `src/app/api/health/route.ts` are [verbatim]
- [ ] `src/lib/utils/index.ts` is [verbatim]
- [ ] `src/lib/constants/env.ts` is [verbatim] (isDev constant — must be exact)
- [ ] `.gitignore` is [verbatim]
- [ ] `vitest.config.ts` is [verbatim]
- [ ] `postcss.config.mjs` is [verbatim]
- [ ] Package install section uses `pnpm add <names>` with no version numbers
- [ ] Scaffold steps section runs `pnpm typecheck && pnpm test` as the verification gate before generating AGENTS.md

**Verify:** Scaffold a new Next.js project using only this skill (no templates/ directory). Run `pnpm build` in the scaffolded project → zero errors.

**Steps:**

- [ ] **Step 1: Identify current [generate] targets that need [verbatim] promotion**

Current [generate] files in the skill that need promotion:
```
layout.tsx               → [verbatim — Part C]
src/app/api/route.ts     → [verbatim — Part C]
src/app/api/health/route.ts → [verbatim — Part C]
src/lib/utils/index.ts   → [verbatim — Part C]  (note: skill says utils.ts, template has utils/index.ts — align to index.ts)
src/lib/constants/env.ts → [verbatim — Part C]
.gitignore               → [verbatim — Part B]
vitest.config.ts         → [verbatim — Part B]
postcss.config.mjs       → [verbatim — Part B]
```

Keep as [generate] (flexible enough to be reliable):
```
globals.css              — [generate] with explicit CSS vars + keyframe spec is fine
(public)/layout.tsx      — [generate] navbar+footer composition is reliable
(public)/page.tsx        — [generate] landing page, user will customise
navbar.tsx               — [generate]
site-footer.tsx          — [generate]
features/example/        — [generate] entire subtree
routes.ts                — [generate]
```

- [ ] **Step 2: Write verbatim content for each promoted file**

For each file being promoted, write the exact content as a Part B or Part C block. Use the current content from `templates/nextjs/src/` as the source (these files are already correct from previous session work).

**`layout.tsx` verbatim block:**
```tsx
import { Providers, ThemeProvider } from '@/components/layout';
import type { Metadata } from 'next';
import { Geist_Mono, Lato } from 'next/font/google';
import './globals.css';

const lato = Lato({
  variable: '--font-lato',
  subsets: ['latin'],
  weight: ['100', '300', '400', '700', '900'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: '<project-name>',
  description: 'A Next.js application',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning className="no-scrollbar">
      <body className={`${lato.variable} ${geistMono.variable} relative antialiased`}>
        <ThemeProvider attribute="class" defaultTheme="light" disableTransitionOnChange>
          <Providers>{children}</Providers>
        </ThemeProvider>
      </body>
    </html>
  );
}
```

**`src/app/api/route.ts` verbatim block:**
```ts
import { type NextRequest, NextResponse } from 'next/server';

export async function GET(_req: NextRequest): Promise<NextResponse> {
  return NextResponse.json(
    { status: 'ok', timestamp: new Date().toISOString() },
    { status: 200 },
  );
}
```

**`src/app/api/health/route.ts` verbatim block:** (identical to above)

**`src/lib/utils/index.ts` verbatim block:**
```ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

**`src/lib/constants/env.ts` verbatim block:**
```ts
export const isDev = process.env.NODE_ENV === 'development';
```

- [ ] **Step 3: Update package install section**

Find the "Runtime deps" list in the skill. Replace any version-pinned install command with:

```bash
pnpm add @hookform/resolvers @tanstack/react-query axios class-variance-authority clsx lucide-react next next-themes react react-dom react-hook-form tailwind-merge zod
```

Replace devDependency install with:

```bash
pnpm add -D @tailwindcss/postcss @tailwindcss/typography @types/node @types/react @types/react-dom @vitest/coverage-v8 eslint eslint-config-next eslint-config-prettier husky prettier prettier-plugin-organize-imports prettier-plugin-tailwindcss tailwindcss tw-animate-css typescript vitest
```

Remove any `pnpm-lock.yaml` verbatim section from the skill (the lockfile is generated at install time, not by the skill).

- [ ] **Step 4: Update scaffold steps verification gate**

In the "Scaffold Steps" section, ensure Step 5 (or equivalent) reads:

```
Run the quality gate — do not generate AGENTS.md until this passes:

  pnpm typecheck   → zero errors
  pnpm lint        → zero errors
  pnpm test        → all tests pass

If typecheck fails with module-not-found errors, a pnpm add is missing.
If lint fails, a generated file violates the eslint config.
```

- [ ] **Step 5: Smoke-test the updated skill**

In a temp directory outside the repo, ask Claude to scaffold a new Next.js project using ONLY `skills/nextjs-scaffold/SKILL.md` (pretend `templates/nextjs/` doesn't exist). Verify:

```bash
cd /tmp/test-nextjs-scaffold
pnpm install
pnpm typecheck   # zero errors
pnpm lint        # zero errors
pnpm test        # 2 tests pass
```

- [ ] **Step 6: Commit**

```bash
git add skills/nextjs-scaffold/SKILL.md
git commit -m "feat(nextjs-scaffold): promote security-critical files to verbatim, remove version pins"
```

---

## Task 4: Rewrite FastAPI scaffold — full verbatim, no rsync

**Goal:** Replace the `rsync templates/fastapi/` approach with a fully self-contained skill that generates every project file from verbatim blocks or precise generation rules.

**Files:**
- Modify: `skills/fastapi-scaffold/SKILL.md` (full rewrite)

**Acceptance Criteria:**
- [ ] Zero references to `rsync`, `templates/fastapi/`, or `<repo-root>` in the skill
- [ ] Every security-critical file has a verbatim block: Dockerfile, docker-entrypoint.sh, .gitignore, .env.example, src/.env.default, src/main.py, src/app.py, src/core/config.py, src/core/exceptions.py, src/error_handler.py
- [ ] Package install uses `pip install <names>` with no version pins
- [ ] Skill includes a requirements.txt generation step: after `pip install`, run `pip freeze > requirements.txt`
- [ ] AGENTS.md generation step included at the end, after all verification gates pass
- [ ] Scaffolded project starts cleanly: `python src/main.py` → API responds at localhost:8000

**Verify:** In `/tmp/test-fastapi`, scaffold using only the skill. Run:
```bash
source .venv/bin/activate
pytest test/ -v   # all tests pass
ruff check src/   # zero lint errors
```

**Steps:**

- [ ] **Step 1: Define the full directory structure**

Write the Part A structure map for the rewritten skill. Every file must be labelled [verbatim] or [generate]:

```
<project-name>/
├── Dockerfile                    [verbatim]
├── docker-entrypoint.sh          [verbatim]
├── .dockerignore                 [verbatim]
├── .gitignore                    [verbatim]
├── .env.example                  [verbatim]
├── pyproject.toml                [verbatim]   ← ruff + mypy config only, no version deps
├── requirements.txt              [generate — pip freeze output after install]
├── requirements-dev.txt          [verbatim — package names only, no versions]
├── README.md                     [generate]
├── AGENTS.md                     [generate — after verification gate]
└── src/
    ├── .env.default              [verbatim]
    ├── main.py                   [verbatim]
    ├── app.py                    [verbatim]
    ├── error_handler.py          [verbatim]
    ├── core/
    │   ├── __init__.py           [verbatim — empty]
    │   ├── config.py             [verbatim]
    │   ├── exceptions.py         [verbatim]
    │   ├── logging.py            [verbatim]
    │   └── json/logging.json     [verbatim]
    ├── api/
    │   ├── __init__.py           [verbatim — empty]
    │   ├── routes.py             [verbatim]
    │   ├── tags.py               [verbatim]
    │   ├── routers/
    │   │   ├── __init__.py       [verbatim — empty]
    │   │   └── example.py        [verbatim]
    │   ├── schemas/
    │   │   ├── __init__.py       [verbatim — empty]
    │   │   ├── base.py           [verbatim]
    │   │   ├── request/
    │   │   │   ├── __init__.py   [verbatim — empty]
    │   │   │   └── example.py    [verbatim]
    │   │   └── response/
    │   │       ├── __init__.py   [verbatim — empty]
    │   │       └── example.py    [verbatim]
    │   └── services/
    │       ├── __init__.py       [verbatim — empty]
    │       └── example.py        [verbatim]
    ├── constants/
    │   └── __init__.py           [verbatim — empty]
    ├── logic/
    │   └── __init__.py           [verbatim — empty]
    ├── models/
    │   ├── __init__.py           [verbatim — empty]
    │   └── base.py               [verbatim]
    └── utils/
        ├── __init__.py           [verbatim — empty]
        └── date.py               [verbatim]
test/
    ├── conftest.py               [verbatim]
    ├── factories/
    │   ├── __init__.py           [verbatim — empty]
    │   └── models.py             [verbatim]
    └── test_api/
        ├── __init__.py           [verbatim — empty]
        ├── test_example.py       [verbatim]
        └── test_health.py        [verbatim]
```

Note: `src/log/` is NOT scaffolded — it is gitignored and created at runtime.

- [ ] **Step 2: Write Part B — verbatim content for every [verbatim] file**

Source the exact content from `templates/fastapi/` for each file. Key security rules to verify while copying:

**Dockerfile** — must use non-root user:
```dockerfile
# Final stage must contain:
RUN adduser --disabled-password --gecos "" appuser
USER appuser
```

**docker-entrypoint.sh** — must be `chmod +x` and not expose secrets.

**.gitignore** — must include: `.env`, `.env.local`, `*.env`, `.venv/`, `__pycache__/`, `*.pyc`, `log/`, `*.log`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`

**src/core/config.py** — must use `pydantic-settings` `BaseSettings`, must never have hardcoded secrets, must document which env vars are required.

**src/error_handler.py** — must NOT expose internal error details or stack traces to HTTP clients. Must use generic messages.

- [ ] **Step 3: Write install steps (no version pins)**

```bash
# 1. Create virtual environment
python -m venv .venv
source .venv/bin/activate   # Linux/Mac
# .venv\Scripts\activate    # Windows

# 2. Install runtime deps (no versions — resolves latest)
pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart python-json-logger

# 3. Install dev deps
pip install pytest httpx ruff mypy

# 4. Lock versions for reproducibility
pip freeze > requirements.txt
```

- [ ] **Step 4: Write verification gate**

```bash
# All must pass before generating AGENTS.md
pytest test/ -v         # all tests green
ruff check src/         # zero lint errors
python src/main.py &    # starts without error
curl localhost:8000/health  # returns {"status":"healthy"}
kill %1
```

- [ ] **Step 5: Write AGENTS.md generation step**

Instruct Claude to generate `AGENTS.md` at project root with:
- `<!-- templateCentral: fastapi@<today-date> -->` on line 1
- Full architecture section (layered: api/ → services → models, core/ is standalone)
- Skills table: fastapi-scaffold (done), fastapi-add-endpoint, fastapi-add-auth, fastapi-add-database, fastapi-add-integration, fastapi-add-test
- Project-specific notes section (blank)

- [ ] **Step 6: Commit**

```bash
git add skills/fastapi-scaffold/SKILL.md
git commit -m "feat(fastapi-scaffold): rewrite as fully self-contained skill, no templates/ dependency"
```

---

## Task 5: Rewrite NestJS scaffold — full verbatim, no rsync

**Goal:** Same as Task 4 but for NestJS. Replace `rsync templates/nestjs/` with fully self-contained verbatim skill.

**Files:**
- Modify: `skills/nestjs-scaffold/SKILL.md` (full rewrite)

**Acceptance Criteria:**
- [ ] Zero references to `rsync` or `templates/nestjs/`
- [ ] Security-critical verbatim files: Dockerfile, docker-entrypoint.sh, .gitignore, .env.example, src/main.ts, src/config/env.config.ts, src/common/filters/http-exception.filter.ts, src/config/setups/security.setup.ts
- [ ] Package install uses `pnpm add <names>` with no version pins
- [ ] Scaffolded project: `pnpm build` succeeds, `pnpm test` passes

**Verify:** In `/tmp/test-nestjs`, scaffold using only the skill:
```bash
pnpm build   # zero errors
pnpm test    # all pass
```

**Steps:**

- [ ] **Step 1: Define the full directory structure**

Write Part A. Every file labelled [verbatim] or [generate]:

```
<project-name>/
├── Dockerfile                    [verbatim]
├── docker-entrypoint.sh          [verbatim]
├── .dockerignore                 [verbatim]
├── .gitignore                    [verbatim]   ← must exclude dist/, .env
├── .env.example                  [verbatim]
├── .prettierrc                   [verbatim]
├── eslint.config.mjs             [verbatim]
├── nest-cli.json                 [verbatim]
├── package.json                  [generate — name from input, pnpm add for deps]
├── tsconfig.json                 [verbatim]
├── tsconfig.build.json           [verbatim]
├── README.md                     [generate]
├── AGENTS.md                     [generate — after verification gate]
├── .husky/
│   ├── pre-commit                [verbatim]
│   └── pre-push                  [verbatim]
└── src/
    ├── main.ts                   [verbatim]
    ├── app.module.ts             [verbatim]
    ├── common/
    │   ├── constants/
    │   │   ├── http.constants.ts [verbatim]
    │   │   └── index.ts          [verbatim]
    │   ├── filters/
    │   │   └── http-exception.filter.ts [verbatim]
    │   └── utils/
    │       ├── date.utils.ts     [verbatim]
    │       └── string.utils.ts   [verbatim]
    ├── config/
    │   ├── env.config.ts         [verbatim]
    │   ├── index.ts              [verbatim]
    │   └── setups/
    │       ├── security.setup.ts [verbatim]
    │       └── swagger.setup.ts  [verbatim]
    └── modules/
        ├── index.ts              [verbatim]
        ├── base/
        │   ├── base.controller.ts [verbatim]
        │   ├── base.module.ts     [verbatim]
        │   └── base.service.ts    [verbatim]
        └── example/
            ├── example.controller.ts [verbatim]
            ├── example.dto.ts        [verbatim]
            ├── example.module.ts     [verbatim]
            ├── example.repository.ts [verbatim]
            ├── example.service.ts    [verbatim]
            └── example.types.ts      [verbatim]
test/
    ├── app.e2e-spec.ts           [verbatim]
    ├── jest-e2e.json             [verbatim]
    └── modules/
        ├── base.controller.spec.ts    [verbatim]
        └── example.controller.spec.ts [verbatim]
```

Note: **Do NOT include `dist/` in the skill** — it is compiler output and must be gitignored.

- [ ] **Step 2: Write Part B and Part C verbatim content**

Source every [verbatim] file from `templates/nestjs/`. Security checks:

**Dockerfile** — non-root user in final stage, no secrets in image layers.

**.gitignore** — must include `dist/`, `.env`, `*.env`, `node_modules/`, `coverage/`.

**src/config/setups/security.setup.ts** — copy exactly; this configures Helmet + CORS + rate limiting.

**src/common/filters/http-exception.filter.ts** — copy exactly; this determines what error info reaches clients.

- [ ] **Step 3: Write install steps**

```bash
pnpm add @nestjs/common @nestjs/core @nestjs/platform-fastify @nestjs/swagger \
  @nestjs/throttler fastify fastify-plugin nestjs-zod reflect-metadata rxjs zod

pnpm add -D @nestjs/cli @nestjs/testing @types/node typescript \
  eslint eslint-config-prettier prettier husky
```

- [ ] **Step 4: Verification gate + AGENTS.md generation**

```bash
pnpm build        # zero compile errors
pnpm test         # all unit tests pass
pnpm test:e2e     # e2e tests pass
```

Only generate AGENTS.md after all gates pass.

- [ ] **Step 5: Commit**

```bash
git add skills/nestjs-scaffold/SKILL.md
git commit -m "feat(nestjs-scaffold): rewrite as fully self-contained skill, no templates/ dependency"
```

---

## Task 6: Rewrite Vite-React scaffold — full verbatim, no rsync

**Goal:** Same pattern as Tasks 4-5 for the Vite + React SPA template.

**Files:**
- Modify: `skills/vite-react-scaffold/SKILL.md` (full rewrite)

**Acceptance Criteria:**
- [ ] Zero references to `rsync` or `templates/vite-react/`
- [ ] Security-critical verbatim files: Dockerfile, docker-entrypoint.sh, .gitignore, nginx.conf.template, src/lib/constants/env.ts (never `process.env`)
- [ ] Package install uses `pnpm add <names>` with no version pins
- [ ] Auth included by default in vite-react scaffold (it's a client-only SPA, auth is part of the routing structure from the start)
- [ ] Scaffolded project: `pnpm build` succeeds, `pnpm test` passes

**Verify:** In `/tmp/test-vite-react`, scaffold using only the skill:
```bash
pnpm build   # zero errors
pnpm test    # all pass
```

**Steps:**

- [ ] **Step 1: Define full directory structure**

```
<project-name>/
├── Dockerfile                    [verbatim]
├── docker-entrypoint.sh          [verbatim]
├── .dockerignore                 [verbatim]
├── .gitignore                    [verbatim]
├── .env.example                  [verbatim]
├── .prettierrc                   [verbatim]
├── eslint.config.mjs             [verbatim]
├── nginx.conf.template           [verbatim]   ← security: headers, no directory listing
├── index.html                    [verbatim]
├── vite.config.ts                [verbatim]
├── tsconfig.json                 [verbatim]
├── components.json               [verbatim]
├── package.json                  [generate — name from input, pnpm add for deps]
├── postcss.config.mjs            [verbatim]
├── vite-env.d.ts                 [verbatim]
├── README.md                     [generate]
├── AGENTS.md                     [generate — after verification gate]
├── .husky/
│   ├── pre-commit                [verbatim]
│   └── pre-push                  [verbatim]
└── src/
    ├── main.tsx                  [verbatim]
    ├── app.tsx                   [verbatim]
    ├── router.tsx                [verbatim]
    ├── styles/globals.css        [verbatim]
    ├── test/setup.ts             [verbatim]
    ├── pages/
    │   ├── index.ts              [verbatim]
    │   ├── home.tsx              [verbatim]
    │   ├── login.tsx             [verbatim]
    │   ├── dashboard.tsx         [verbatim]
    │   └── not-found.tsx         [verbatim]
    ├── features/
    │   ├── auth/
    │   │   ├── index.ts          [verbatim]
    │   │   ├── types.ts          [verbatim]
    │   │   ├── components/
    │   │   │   ├── index.ts      [verbatim]
    │   │   │   ├── auth-provider.tsx  [verbatim]
    │   │   │   ├── login-card.tsx     [verbatim]
    │   │   │   └── protected-route.tsx [verbatim]
    │   │   └── hooks/
    │   │       ├── index.ts      [verbatim]
    │   │       └── use-auth.ts   [verbatim]
    │   └── example/              [verbatim — full subtree]
    ├── components/
    │   ├── layout/
    │   │   ├── index.ts          [verbatim]
    │   │   ├── error-boundary.tsx [verbatim]
    │   │   ├── navbar.tsx        [verbatim]
    │   │   ├── providers.tsx     [verbatim]
    │   │   ├── root-layout.tsx   [verbatim]
    │   │   └── site-footer.tsx   [verbatim]
    │   └── widgets/              [verbatim — full subtree]
    ├── lib/
    │   ├── clients/
    │   │   └── fetch-client.ts   [verbatim]
    │   ├── constants/
    │   │   ├── index.ts          [verbatim]
    │   │   ├── env.ts            [verbatim]   ← MUST use import.meta.env.VITE_*
    │   │   └── routes.ts         [verbatim]
    │   ├── errors/
    │   │   ├── api-error.ts      [verbatim]
    │   │   ├── error-log-handler.ts [verbatim]
    │   │   └── index.ts          [verbatim]
    │   └── utils/
    │       └── index.ts          [verbatim]
    └── hooks/
        └── index.ts              [verbatim]
```

- [ ] **Step 2: Write Part B and Part C verbatim blocks**

Source from `templates/vite-react/`. Key security rules to verify:

**nginx.conf.template** — must include:
- `X-Frame-Options DENY`
- `X-Content-Type-Options nosniff`
- No directory listing (`autoindex off`)
- No server version disclosure (`server_tokens off`)

**src/lib/constants/env.ts** — must ONLY use `import.meta.env.VITE_*`, never `process.env`:
```ts
export const ENV = {
  BASE_URL: import.meta.env.VITE_BASE_URL ?? '',
  IS_DEV: import.meta.env.DEV,
} as const;
```

**features/auth/components/auth-provider.tsx** — the dev bypass (`ENV.IS_DEV`) is intentional and must be preserved with a comment explaining it:
```ts
// Dev bypass: in development, skip the API call and use a mock user.
// Remove this block and the IS_DEV guard before going to production.
if (ENV.IS_DEV) { ... }
```

- [ ] **Step 3: Write install steps**

```bash
pnpm add react react-dom react-router-dom @tanstack/react-query axios \
  class-variance-authority clsx tailwind-merge lucide-react \
  @hookform/resolvers react-hook-form zod

pnpm add -D vite @vitejs/plugin-react typescript \
  @types/react @types/react-dom \
  tailwindcss @tailwindcss/postcss @tailwindcss/typography tw-animate-css \
  eslint eslint-config-prettier prettier prettier-plugin-tailwindcss \
  vitest @vitest/coverage-v8 @testing-library/react @testing-library/jest-dom \
  husky
```

- [ ] **Step 4: Verification gate + AGENTS.md generation**

```bash
pnpm build      # zero errors
pnpm typecheck  # zero errors
pnpm test       # all pass
```

- [ ] **Step 5: Commit**

```bash
git add skills/vite-react-scaffold/SKILL.md
git commit -m "feat(vite-react-scaffold): rewrite as fully self-contained skill, no templates/ dependency"
```

---

## Task 7: Delete templates/, mcp-server/; update plugin.json

**Goal:** Remove `templates/` and `mcp-server/` from the repo, update plugin.json to register all 46 skills, and confirm the `.mcp.json` reflects the new state.

**Files:**
- Delete: `templates/` (entire directory)
- Delete: `mcp-server/` (entire directory)
- Delete: `.mcp.json`
- Modify: `.claude-plugin/plugin.json` — add skills list, bump version to 2.0.0
- Modify: `.claude-plugin/marketplace.json` — update description
- Modify: `.gitignore` — remove `mcp-server/dist` if present
- Modify: `README.md` — rewrite usage section

**Acceptance Criteria:**
- [ ] `templates/` does not exist
- [ ] `mcp-server/` does not exist
- [ ] `.mcp.json` does not exist
- [ ] `plugin.json` lists all 46 skill names under a `skills` key
- [ ] `plugin.json` version is `2.0.0`
- [ ] README install instructions say "install the plugin" with no mention of cloning

**Verify:** `find . -name "*.ts" -path "*/mcp-server/*"` → zero results. `cat .claude-plugin/plugin.json | python3 -m json.tool` → valid JSON.

**Steps:**

- [ ] **Step 1: Confirm scaffold skills are self-sufficient (pre-delete check)**

Before deleting templates/, run each scaffold skill end-to-end in a temp directory and verify the project builds (Tasks 3-6 must be complete first). If any skill still references templates/, fix it before proceeding.

- [ ] **Step 2: Delete templates/ and mcp-server/**

```bash
git rm -r templates/
git rm -r mcp-server/
git rm .mcp.json
```

- [ ] **Step 3: Update plugin.json**

```json
{
  "name": "templatecentral",
  "version": "2.0.0",
  "description": "Production-ready project scaffolding for Next.js, Vite-React, FastAPI, and NestJS. Install once, scaffold anywhere — no repo cloning required.",
  "author": { "name": "Clarence" },
  "keywords": ["scaffold", "nextjs", "fastapi", "nestjs", "vite-react", "templates"],
  "skills": [
    "fastapi-add-auth", "fastapi-add-database", "fastapi-add-endpoint",
    "fastapi-add-integration", "fastapi-add-test", "fastapi-code-standards",
    "fastapi-scaffold",
    "nestjs-add-auth", "nestjs-add-database", "nestjs-add-integration",
    "nestjs-add-module", "nestjs-add-test", "nestjs-code-standards",
    "nestjs-scaffold",
    "nextjs-add-api-route", "nextjs-add-auth", "nextjs-add-component",
    "nextjs-add-database", "nextjs-add-feature", "nextjs-add-form",
    "nextjs-add-integration", "nextjs-add-page", "nextjs-add-test",
    "nextjs-code-standards", "nextjs-scaffold",
    "shared-add-error-handling", "shared-add-logging", "shared-add-pagination",
    "shared-build-agent", "shared-drift-check", "shared-full-stack-pairing",
    "shared-remove-example", "shared-review-agent", "shared-task-management",
    "shared-test-agent", "shared-update-agent", "shared-validation-patterns",
    "vite-react-add-auth", "vite-react-add-component", "vite-react-add-feature",
    "vite-react-add-form", "vite-react-add-integration", "vite-react-add-page",
    "vite-react-add-test", "vite-react-code-standards", "vite-react-scaffold"
  ]
}
```

- [ ] **Step 4: Update README.md**

Rewrite the "Getting Started" section to say:

1. Install the templateCentral plugin in Claude Code
2. Ask Claude: "Scaffold a new Next.js project at ~/projects/my-app"
3. Claude reads `nextjs-scaffold`, generates all files, runs verification

Remove all sections about cloning the repo, MCP server setup, and `node dist/index.js`.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/ README.md .gitignore
git commit -m "feat: complete plugin-first migration — remove templates/, mcp-server/, upgrade plugin to v2"
```

---

## Task 8: End-to-end smoke test — all four stacks

**Goal:** Verify every scaffold skill produces a working project from scratch, using no files from this repo other than the plugin-installed skills.

**Files:**
- No repo files modified — this is a verification task only

**Acceptance Criteria:**
- [ ] Next.js scaffold → `pnpm build` passes, `pnpm test` passes, dev server starts
- [ ] FastAPI scaffold → `pytest test/` passes, `ruff check` clean, API starts
- [ ] NestJS scaffold → `pnpm build` passes, `pnpm test` and `pnpm test:e2e` pass
- [ ] Vite-React scaffold → `pnpm build` passes, `pnpm test` passes
- [ ] Each scaffolded project has a valid `AGENTS.md` with `<!-- templateCentral: <stack>@<date> -->` on line 1
- [ ] No scaffolded project imports from a missing package (zero TypeScript/Python import errors)

**Verify:** All four stacks pass their respective build + test commands.

**Steps:**

- [ ] **Step 1: Create four isolated test directories**

```bash
mkdir /tmp/tc-smoke-test
cd /tmp/tc-smoke-test
mkdir nextjs-test fastapi-test nestjs-test vite-react-test
```

- [ ] **Step 2: Scaffold each project**

For each stack, open a Claude Code session in the test directory and invoke the scaffold skill:
- `templatecentral:nextjs-scaffold` → target `/tmp/tc-smoke-test/nextjs-test`
- `templatecentral:fastapi-scaffold` → target `/tmp/tc-smoke-test/fastapi-test`
- `templatecentral:nestjs-scaffold` → target `/tmp/tc-smoke-test/nestjs-test`
- `templatecentral:vite-react-scaffold` → target `/tmp/tc-smoke-test/vite-react-test`

- [ ] **Step 3: Run verification for each stack**

**Next.js:**
```bash
cd /tmp/tc-smoke-test/nextjs-test
pnpm install && pnpm typecheck && pnpm lint && pnpm test && pnpm build
```

**FastAPI:**
```bash
cd /tmp/tc-smoke-test/fastapi-test
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
pytest test/ -v && ruff check src/
```

**NestJS:**
```bash
cd /tmp/tc-smoke-test/nestjs-test
pnpm install && pnpm build && pnpm test && pnpm test:e2e
```

**Vite-React:**
```bash
cd /tmp/tc-smoke-test/vite-react-test
pnpm install && pnpm typecheck && pnpm test && pnpm build
```

- [ ] **Step 4: Verify AGENTS.md in each project**

```bash
for dir in nextjs-test fastapi-test nestjs-test vite-react-test; do
  echo "=== $dir ===" && head -1 /tmp/tc-smoke-test/$dir/AGENTS.md
done
```

Expected: each prints `<!-- templateCentral: <stack>@2026-XX-XX -->`.

- [ ] **Step 5: Document any failures and fix**

If any smoke test fails, identify the failing file in the scaffold skill, fix the verbatim block or generation rule, and rerun from Step 2 for that stack.

- [ ] **Step 6: Final commit if any fixes were needed**

```bash
git add skills/
git commit -m "fix: smoke test corrections from plugin-first migration"
```

---

## Security Checklist (applies to all scaffold tasks)

Before marking any scaffold skill task complete, verify every point in this checklist:

**Dockerfile:**
- [ ] Final stage uses a non-root user (`RUN adduser` + `USER`)
- [ ] No `ENV` instructions containing secrets or API keys
- [ ] COPY uses specific paths, not `COPY . .` on the final stage
- [ ] Base image is pinned to a specific minor version (e.g. `node:22-alpine` not `node:latest`)

**Environment files:**
- [ ] `.env.example` contains only placeholder values (no real secrets)
- [ ] `.gitignore` excludes `.env`, `.env.local`, `*.env`, `.env.*`
- [ ] `src/.env.default` (FastAPI) or `.env.example` has a comment explaining each variable

**Error handling:**
- [ ] Error responses never expose stack traces, internal paths, or database query details
- [ ] 500 responses return a generic message (`"Internal server error"` not `err.message`)

**Auth (if present):**
- [ ] No hardcoded credentials or default passwords
- [ ] `AUTH_SECRET` / equivalent is always `openssl rand -base64 32` or equivalent — never a hardcoded string
- [ ] Dev-only bypasses (like Vite-React's `ENV.IS_DEV` guard) are clearly commented

**Secrets in code:**
- [ ] `grep -r "password\|secret\|apikey\|api_key" src/` (or equivalent) returns only config variable *names*, never actual values

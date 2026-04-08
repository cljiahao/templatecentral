---
name: scaffold
description: Use when the user wants to start a new frontend project, create a new Next.js app, or scaffold a React dashboard with shadcn/ui and Docker support.
---

# Scaffold Next.js Project

Scaffold a new Next.js project from the templateCentral Next.js template.

## Inputs

- **Project name** — The name for the new project (e.g., `my-dashboard`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-dashboard`). If not provided, default to `./<project-name>` and confirm with the user.

## Steps

### 1. Copy the Template

Copy the entire `templates/nextjs/` directory from this repository to the target directory. Do NOT copy `node_modules/` or `.next/`.

```bash
rsync -av --exclude='node_modules' --exclude='.next' --exclude='.env' --exclude='.env.local' <repo-root>/templates/nextjs/ <target-directory>/
```

### 2. Update Project Name

In `package.json`, replace the `"name"` field value with the new project name (lowercase, kebab-case).

### 3. Update Metadata

In `src/app/layout.tsx`, update the `metadata` export:
- Set `title` to the project name (title-cased)
- Set `description` to a relevant description

### 4. Update Branding

In `src/components/layout/navbar.tsx`:
- Replace the brand text (`templateCentral`) with the project name
- Keep `defaultNavLinks` defaults unless the user specifies custom navigation. If unclear, ask the user

In `src/components/layout/site-footer.tsx`:
- Update the `creditText` default

### 5. Update Routes

In `src/lib/constants/routes.ts`:
- Keep `PAGE_ROUTES` and `API_ROUTES` defaults unless the user specifies custom routes. If unclear, ask the user

### 6. Update Theme Colors (Optional)

In `src/app/globals.css`, the template uses a neutral palette. Update the CSS custom properties:
- `--primary` and `--primary-hover` — Main action color
- `--secondary` and `--secondary-hover` — Secondary action color
- `--accent` and `--accent-hover` — Accent/highlight color

### 7. Copy `.env.example` to `.env.local`

```bash
cp .env.example .env.local
```

### 8. Install Dependencies

```bash
cd <target-directory>
pnpm install
```

**Checkpoint**: Verify installation completed without errors. If dependency conflicts occur, resolve them before proceeding.

### 9. Verify

```bash
pnpm dev
```

Confirm the dev server starts at `http://localhost:3000`. **Do not proceed until the landing page renders successfully.** If the dev server fails, check the terminal output for errors and fix before continuing.

Then run the test suite:

```bash
pnpm test
```

Confirm all tests pass. `test/api/health.test.ts` covers **`GET /api`** and **`GET /api/health`** (Docker HEALTHCHECK uses the latter).

Then run a production compile:

```bash
pnpm build
```

**Checkpoint**: `pnpm build` must succeed before generating project docs — catches TypeScript and App Router issues that `pnpm dev` may not surface.

Optional full gate: `pnpm check` (format + lint + typecheck).

### 10. Generate Project AGENTS.md (MANDATORY)

**Required** — root `AGENTS.md` Project Memory; only after verification gates pass.

Create `AGENTS.md` in the project root. This gives any AI agent (Cursor, Codex, Copilot, Windsurf, etc.) permanent context about this specific project.

```markdown
# <Project Name>

## Identity
- **Stack**: Next.js 16, React 19, TypeScript, shadcn/ui, Tailwind CSS 4, TanStack React Query, NextAuth
- **Scaffolded from**: templateCentral/templates/nextjs
- **Created**: <date>

## Architecture Decisions
- Auth via NextAuth (Auth.js) with `proxy.ts` route protection (Next.js 16 proxy, replaces middleware); dev bypass when `isDev`
- Providers (SessionProvider, QueryClientProvider) in root `layout.tsx` — shared across all route groups
- Route groups: `(public)/` for public pages, `dashboard/` for authenticated — each has its own Navbar + Footer shell
- Feature modules under `src/features/<name>/`
- Barrel exports (`index.ts`) for all shared folders
- shadcn/ui primitives in `src/components/ui/` (managed by CLI)
- Reusable composed widgets in `src/components/widgets/`
- Health JSON: `GET /api` (`src/app/api/route.ts`) and `GET /api/health` (`src/app/api/health/route.ts`); Docker HEALTHCHECK targets `/api/health`

## Key Conventions
- Named exports only (except Next.js special files: pages, layouts, route handlers)
- `function` declarations for components; `const` arrows for hooks/utilities
- kebab-case filenames, PascalCase exports
- Static data in `constants.ts`, never inline in components
- Pages are thin — compose from `features/` and `components/`
- **Testing (API only)**: New or changed `src/app/api/**` handlers need Vitest tests under `test/api/` in the same change; no mandatory frontend tests

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Update the Identity section with the actual project name and creation date. Add any user-specified customizations (custom routes, theme colors, navigation) under "Project-Specific Notes".

### 11. Generate Project CLAUDE.md (MANDATORY for Claude Code users)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Follow **Scaffold: CLAUDE.md (Claude Code only)** in repository root `AGENTS.md`. Write a **short** `CLAUDE.md` (full architecture/conventions: **`AGENTS.md` only**).

**Build & Dev**, e.g.: `pnpm dev`, `pnpm build`, `pnpm test`, `pnpm lint`, `pnpm format`, `pnpm check` (optional full gate).

**templateCentral skills**: `scaffold` (done), `add-page`, `add-feature`, `add-component`, `add-api-route`, `add-form`, `add-auth`, `add-integration`, `add-database`, `add-test`. **Workflow**: `claude-skills/nextjs/` vs Superpowers — root `AGENTS.md`. **Never** secrets in `CLAUDE.md`.

### 12. Task Management (Optional)

Ask whether the user wants structured task management for complex features. If **yes**, append **Option A** or **Option B** from **Scaffold: optional Task Management** in repository root `AGENTS.md` (templateCentral). If **no**, skip.

### 13. Remove Example Code (Optional)

Once the project is verified and the user confirms it runs:
- Delete `src/features/example/` directory
- Remove the `ExampleList` import and usage from `src/app/dashboard/(overview)/page.tsx`
- Update barrel exports that re-export from the deleted feature

## Rules

- Always update `package.json` name before installing dependencies — affects Docker image names and lockfiles
- Always copy `.env.example` to `.env.local` before first run — **never** commit `.env.local` or paste production secrets into generated `AGENTS.md` / `CLAUDE.md`
- Keep the `(public)` and `dashboard` route group structure
- Verify the dev server starts and the landing page renders before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/`, `.next/`, or `.env.local` — these are project-specific
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user

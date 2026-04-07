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
rsync -av --exclude='node_modules' --exclude='.next' --exclude='.env' <repo-root>/templates/nextjs/ <target-directory>/
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

Confirm all tests pass. The template includes a health check test (`__tests__/api/health.test.ts`) — verify it passes.

### 10. Generate Project AGENTS.md (MANDATORY)

**This step is NOT optional. Do NOT skip it. Scaffolding is incomplete without a project AGENTS.md.**

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
- `/api/health` endpoint for Docker HEALTHCHECK and load balancer probes

## Key Conventions
- Named exports only (except Next.js special files: pages, layouts, route handlers)
- `function` declarations for components; `const` arrows for hooks/utilities
- kebab-case filenames, PascalCase exports
- Static data in `constants.ts`, never inline in components
- Pages are thin — compose from `features/` and `components/`

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Update the Identity section with the actual project name and creation date. Add any user-specified customizations (custom routes, theme colors, navigation) under "Project-Specific Notes".

### 11. Generate Project CLAUDE.md (MANDATORY for Claude Code users)

**This step is NOT optional when the user uses Claude Code.** If the user uses only Cursor/Copilot/Windsurf (no Claude Code), skip this step — `AGENTS.md` is sufficient.

Create `CLAUDE.md` in the project root. Claude Code reads this file automatically at session start and uses it as persistent project context.

```markdown
# <Project Name>

Next.js 16 project scaffolded from templateCentral.

## Build & Dev

- `pnpm dev` — start dev server (Turbopack, http://localhost:3000)
- `pnpm build` — production build
- `pnpm test` — run Vitest suite
- `pnpm lint` — ESLint 9
- `pnpm format` — Prettier formatting
- `pnpm check` — format + lint + typecheck (full quality gate)

## Architecture

- Route groups: `(public)/` for public pages, `dashboard/` for authenticated
- Auth via NextAuth (Auth.js) with `proxy.ts` route protection; dev bypass when `isDev`
- Feature modules: `src/features/<name>/` (components, hooks, api, types)
- UI primitives: `src/components/ui/` (shadcn/ui, managed by CLI)
- Composed widgets: `src/components/widgets/`
- Barrel exports (`index.ts`) in all shared folders
- Providers (SessionProvider, QueryClientProvider) in root `layout.tsx`
- `/api/health` endpoint for Docker HEALTHCHECK and load balancer probes

## Conventions

- Named exports only (except Next.js special files: pages, layouts, route handlers)
- `function` declarations for components; `const` arrows for hooks/utilities
- kebab-case filenames, PascalCase exports
- Pages are thin — compose from `features/` and `components/`
- Static data in `constants.ts`, never inline in components

## Workflow

Use this decision tree for all tasks:

| Task complexity | Approach |
|----------------|----------|
| Simple (add page, component, API route, single-file change) | Follow templateCentral skills directly — see `claude-skills/nextjs/` in templateCentral repo |
| Medium (add feature, add form, add integration) | Follow templateCentral skills — they have complete step-by-step instructions |
| Complex (3+ files, architectural decisions, multi-step feature) | Use Superpowers plugin workflow: `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan` |
| Debugging | Use Superpowers `systematic-debugging` skill if installed, otherwise debug normally |

**Important**: Regardless of which workflow is used, ALL code must follow the conventions above and the patterns in `AGENTS.md`.

## templateCentral Reference

This project was scaffolded from `templateCentral/templates/nextjs`. Available skills for this stack:

- `scaffold` — initial project setup (already done)
- `add-page` — add a new page/route
- `add-feature` — add a feature module
- `add-component` — add a shared component
- `add-api-route` — add an API route handler
- `add-form` — add a form with validation
- `add-auth` — add/modify authentication
- `add-integration` — add external API integration
- `add-database` — add Prisma (SQL) or Mongoose (MongoDB)
- `add-test` — add tests for API route handlers (backend only)
```

Update the project name and customize the skills list if any don't apply.

### 12. Task Management (Optional)

Ask the user: *"Do you want structured task management for complex features? You have two options:"*

**Option A — templateCentral built-in** (no plugin required):

Append to the project's `AGENTS.md`:

```markdown
## Task Management

For complex, multi-step tasks (3+ files, architectural decisions), follow the task management protocol at `claude-skills/shared/task-management/SKILL.md` in templateCentral.

Protocol summary: Plan → Verify → Track → Explain → Document → Capture Lessons.

Skip for simple changes (single-file edits, scaffolding, quick fixes).
```

**Option B — Superpowers plugin** (recommended for Claude Code users building complex features):

Tell the user to install Superpowers in their Claude Code session:

```bash
/plugin marketplace add pcvelz/superpowers
/plugin install superpowers-extended-cc@superpowers-extended-cc-marketplace
```

Then append to the project's `AGENTS.md`:

```markdown
## Task Management

- **Simple tasks** (add-page, add-component, add-api-route): use templateCentral skills directly
- **Complex features** (3+ files, architectural decisions): use Superpowers workflow — `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`
- All code must follow the conventions in this file and the project's code-standards, regardless of workflow used
```

If the user doesn't want either, skip this step entirely.

### 13. Remove Example Code (Optional)

Once the project is verified and the user confirms it runs:
- Delete `src/features/example/` directory
- Remove the `ExampleList` import and usage from `src/app/dashboard/(overview)/page.tsx`
- Update barrel exports that re-export from the deleted feature

## Rules

- Always update `package.json` name before installing dependencies — affects Docker image names and lockfiles
- Always copy `.env.example` to `.env.local` before first run
- Keep the `(public)` and `dashboard` route group structure
- Verify the dev server starts and the landing page renders before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/`, `.next/`, or `.env.local` — these are project-specific
- NEVER scaffold into a non-empty directory without confirming with the user
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user

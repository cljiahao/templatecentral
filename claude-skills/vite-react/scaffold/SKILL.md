---
name: scaffold
description: Use when the user wants a lightweight React SPA without SSR, or needs a Vite + React + TypeScript starter with React Router and TanStack Query.
---

# Scaffold Vite + React Project

Scaffold a new Vite + React SPA from the templateCentral Vite React template.

## Inputs

- **Project name** — The name for the new project (e.g., `my-app`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-app`). If not provided, default to `./<project-name>` and confirm with the user.

## Steps

### 1. Copy the Template

```bash
rsync -av --exclude='node_modules' --exclude='dist' --exclude='.env' --exclude='.env.local' <repo-root>/templates/vite-react/ <target-directory>/
```

### 2. Update Project Name

In `package.json`, replace the `"name"` field with the new project name (lowercase, kebab-case):

```json
{
  "name": "my-app",
  ...
}
```

### 3. Update HTML Title

In `index.html`, update the `<title>` tag:

```html
<title>My App</title>
```

### 4. Update Branding

In `src/components/layout/navbar.tsx`:
- Replace `templateCentral` with the project name
- Keep `NAV_LINKS` defaults unless the user specifies custom navigation. If unclear, ask the user

In `src/components/layout/site-footer.tsx`:
- Update the `creditText` default

### 5. Update Routes

In `src/lib/constants/routes.ts`:
- Keep `PAGE_ROUTES` and `API_ROUTES` defaults unless the user specifies custom routes. If unclear, ask the user

In `src/router.tsx`:
- Keep the example `<Routes>` unless the user specifies custom pages

### 6. Update Theme Colors (Optional)

In `src/styles/globals.css`, update the CSS custom properties under `:root`:
- `--primary` / `--primary-hover` — Main action color
- `--secondary` / `--secondary-hover` — Secondary color
- `--accent` / `--accent-hover` — Accent color

### 7. Set Up Environment

```bash
cp .env.example .env
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

Confirm the dev server starts at `http://localhost:3000`. **Do not proceed until the home page renders successfully.** If the dev server fails, check the terminal output for errors and fix before continuing.

```bash
pnpm test
```

**Checkpoint**: All tests must pass.

```bash
pnpm build
```

**Checkpoint**: `pnpm build` must succeed before generating `AGENTS.md` — `tsc -b` catches type errors Vite dev can miss.

### 10. Generate Project AGENTS.md (MANDATORY)

**Required** — root `AGENTS.md` Project Memory; only after verification gates pass.

Create `AGENTS.md` in the project root. This gives any AI agent (Cursor, Codex, Copilot, Windsurf, etc.) permanent context about this specific project.

```markdown
# <Project Name>

## Identity
- **Stack**: Vite 8, React 19, TypeScript, shadcn/ui, Tailwind CSS 4, React Router 7, TanStack React Query 5, React Hook Form + Zod, AuthProvider
- **Scaffolded from**: templateCentral/templates/vite-react
- **Created**: <date>
- **Type**: Client-side SPA (no SSR, no API route handlers)

## Architecture Decisions
- Routes defined in `src/router.tsx`, not by filesystem convention
- Auth via `AuthProvider` context + `ProtectedRoute` guard; dev bypass when `ENV.IS_DEV`
- Feature modules under `src/features/<name>/`
- Barrel exports (`index.ts`) for all shared folders
- shadcn/ui primitives in `src/components/ui/` (managed by CLI, `components.json` with `rsc: false`)
- Reusable composed widgets in `src/components/widgets/`
- Env vars via `import.meta.env.VITE_*`, centralized in `src/lib/constants/env.ts`

## Key Conventions
- Named exports only (default exports allowed in tooling configs: `vite.config.ts`, `eslint.config.mjs`)
- `function` declarations for components; `const` arrows for hooks/utilities
- kebab-case filenames, PascalCase exports
- Static data in `constants.ts`, never inline in components
- Pages are thin — compose from `features/` and `components/`
- **Env**: `VITE_*` is shipped to the browser — never API keys, tokens, or secrets (use server-side or proxy for those)

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Update the Identity section with the actual project name and creation date. Add any user-specified customizations under "Project-Specific Notes".

### 11. Generate Project CLAUDE.md (MANDATORY for Claude Code users)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Follow **Scaffold: CLAUDE.md (Claude Code only)** in repository root `AGENTS.md`. Write a **short** `CLAUDE.md` (full detail in **`AGENTS.md`**).

**Build & Dev**, e.g.: `pnpm dev`, `pnpm build`, `pnpm test`, `pnpm lint`, `pnpm format`.

**templateCentral skills**: `scaffold` (done), `add-page`, `add-feature`, `add-component`, `add-form`, `add-auth`, `add-integration`, `add-test`. **Workflow**: `claude-skills/vite-react/` vs Superpowers — root `AGENTS.md`. **Never** secrets in `CLAUDE.md`.

### 12. Task Management (Optional)

Ask whether the user wants structured task management for complex features. If **yes**, append **Option A** or **Option B** from **Scaffold: optional Task Management** in repository root `AGENTS.md` (templateCentral). If **no**, skip.

### 13. Remove Example Code (Optional)

Once the project is verified and the user confirms it runs:
- Delete `src/features/example/` directory
- Remove the `ExampleList` import and usage from `src/pages/dashboard.tsx`
- Update `src/pages/index.ts` if it re-exports anything from the deleted feature

Or use the shared `remove-example` skill: `claude-skills/shared/remove-example/SKILL.md`.

## Rules

- Always update `package.json` name before installing dependencies
- Always copy `.env.example` to `.env` before first run — **never** commit `.env` or paste secrets into `AGENTS.md` / `CLAUDE.md`
- Always update `index.html` title — it's the browser tab name (NEVER skip)
- Routes are defined in `src/router.tsx`, not by filesystem convention
- Verify the dev server starts and the home page renders before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/` or `dist/` when scaffolding
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user

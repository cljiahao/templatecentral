---
name: scaffold
description: Use when the user wants to start a new NestJS backend project, create a new API, or scaffold a project with modular architecture and Docker support.
---

# Scaffold NestJS Project

Scaffold a new NestJS backend project from the templateCentral NestJS template.

## Inputs

- **Project name** — The name for the new project (e.g., `my-api`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-api`). If not provided, default to `./<project-name>` and confirm with the user.

## Steps

### 1. Copy the Template

Copy the entire `templates/nestjs/` directory from this repository to the target directory. Exclude `node_modules/`, `dist/`, and `.env`.

```bash
rsync -av --exclude='node_modules' --exclude='dist' --exclude='.env' <repo-root>/templates/nestjs/ <target-directory>/
```

### 2. Update Project Settings

In `package.json`, update:
- `name` — Set to the project name

In `src/config/env.config.ts`, update the defaults:

```typescript
export const appConfig = {
  PROJECT_NAME: process.env.PROJECT_NAME || 'My Project',
  PROJECT_DESCRIPTION:
    process.env.PROJECT_DESCRIPTION || 'API built with [NestJS](https://nestjs.com/) + Fastify',
  // ...
};
```

In `.env.example`, update:

```env
PROJECT_NAME=my-api
PORT=3000
```

### 3. Create Environment File

```bash
cp .env.example .env
```

### 4. Install Dependencies

```bash
pnpm install
```

**Checkpoint**: Verify installation completed without errors. If dependency conflicts occur, resolve them before proceeding.

### 5. Verify

```bash
pnpm start:dev
```

Confirm the API starts at `http://localhost:3000` and Swagger docs are available at `http://localhost:3000/docs`. **Do not proceed until the API responds.**

Run tests:

```bash
pnpm test
pnpm test:e2e
```

**Checkpoint**: All tests must pass. If any fail, fix before proceeding.

### 6. Generate Project AGENTS.md (MANDATORY)

**This step is NOT optional. Do NOT skip it. Scaffolding is incomplete without a project AGENTS.md.**

Create `AGENTS.md` in the project root. This gives any AI agent (Cursor, Codex, Copilot, Windsurf, etc.) permanent context about this specific project.

```markdown
# <Project Name>

## Identity
- **Stack**: NestJS 11, Fastify, Zod + nestjs-zod, Swagger, TypeScript, Jest
- **Scaffolded from**: templateCentral/templates/nestjs
- **Created**: <date>

## Architecture Decisions
- One module per feature under `src/modules/`
- Controller → Service (→ Repository for complex queries); simple CRUD may use ORM directly in services
- DTOs use `createZodDto` from `nestjs-zod` (no class-validator)
- Global pipes and filters in `app.module.ts`; auth guards at controller/route level
- Setup functions (Swagger, security) in `src/config/setups/`

## Key Conventions
- kebab-case filenames (dot-separated), PascalCase classes, camelCase methods
- Named exports only — no `export default`
- Swagger `@ApiTags()` + `@ApiOperation()` on every endpoint
- Barrel exports at `src/modules/index.ts`

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Update the Identity section with the actual project name and creation date.

### 7. Generate Project CLAUDE.md (MANDATORY for Claude Code users)

**This step is NOT optional when the user uses Claude Code.** If the user uses only Cursor/Copilot/Windsurf (no Claude Code), skip this step — `AGENTS.md` is sufficient.

Create `CLAUDE.md` in the project root. Claude Code reads this file automatically at session start and uses it as persistent project context.

```markdown
# <Project Name>

NestJS backend scaffolded from templateCentral.

## Build & Dev

- `pnpm start:dev` — start dev server (http://localhost:3000)
- `pnpm build` — production build
- `pnpm test` — run unit tests (Jest)
- `pnpm test:e2e` — run e2e tests
- `pnpm lint` — ESLint 9 + Prettier

## Architecture

- One module per feature under `src/modules/`
- Controller → Service (→ Repository for complex queries); simple CRUD may use ORM directly in services
- DTOs use `createZodDto` from `nestjs-zod` (no class-validator)
- Global pipes and filters in `app.module.ts`; auth guards at controller/route level
- Setup functions (Swagger, security) in `src/config/setups/`
- Swagger docs at `/docs`

## Conventions

- kebab-case filenames (dot-separated), PascalCase classes, camelCase methods
- Named exports only — no `export default`
- Swagger `@ApiTags()` + `@ApiOperation()` on every endpoint
- Barrel exports at `src/modules/index.ts`

## Workflow

Use this decision tree for all tasks:

| Task complexity | Approach |
|----------------|----------|
| Simple (add endpoint, add DTO, single-file change) | Follow templateCentral skills directly — see `claude-skills/nestjs/` in templateCentral repo |
| Medium (add module, add database, add integration) | Follow templateCentral skills — they have complete step-by-step instructions |
| Complex (3+ files, architectural decisions, multi-step feature) | Use Superpowers plugin workflow: `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan` |
| Debugging | Use Superpowers `systematic-debugging` skill if installed, otherwise debug normally |

**Important**: Regardless of which workflow is used, ALL code must follow the conventions above and the patterns in `AGENTS.md`.

## templateCentral Reference

This project was scaffolded from `templateCentral/templates/nestjs`. Available skills for this stack:

- `scaffold` — initial project setup (already done)
- `add-module` — add a feature module with CRUD
- `add-auth` — add authentication
- `add-database` — add Prisma (SQL) or Mongoose (MongoDB)
- `add-integration` — add external API integration
- `add-test` — add tests for existing code
```

Update the project name and customize the skills list if any don't apply.

### 8. Task Management (Optional)

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

- **Simple tasks** (add endpoint, add DTO): use templateCentral skills directly
- **Complex features** (3+ files, architectural decisions): use Superpowers workflow — `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`
- All code must follow the conventions in this file and the project's code-standards, regardless of workflow used
```

If the user doesn't want either, skip this step entirely.

### 9. Remove Example Code (Optional)

Once the project is verified, remove the example module:
- Delete `src/modules/example/` directory
- Remove `ExampleModule` import and reference from `src/modules/index.ts`
- Remove `ExampleModule` from the `imports` array in `src/app.module.ts`
- Delete `test/modules/example.controller.spec.ts`

## Rules

- Always update `package.json` name before installing dependencies
- Always copy `.env.example` to `.env` before first run
- Global pipes and filters go in `app.module.ts`; auth guards at controller/route level (not global, so health checks remain unprotected)
- Verify the API starts and Swagger docs at `/docs` render before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/`, `dist/`, or `.env` when scaffolding
- NEVER scaffold into a non-empty directory without confirming with the user
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove the `base/` module — it provides the health check endpoint
- NEVER install packages globally — always use pnpm/npm within the project
- NEVER remove `test/` directory structure when cleaning up example code

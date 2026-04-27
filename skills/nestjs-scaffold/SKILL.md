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

Copy the NestJS template files to the target directory. Exclude `node_modules/`, `dist/`, and `.env`.

```bash
rsync -av --exclude='node_modules' --exclude='dist' --exclude='.env' --exclude='.env.local' <repo-root>/templates/nestjs/ <target-directory>/
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

```bash
pnpm build
```

**Checkpoint**: Production build must succeed before generating `AGENTS.md` — catches strict TypeScript errors.

### 6. Generate Project AGENTS.md (MANDATORY)

**Required** — root `AGENTS.md` Project Memory; only after verification gates pass.

Create `AGENTS.md` in the project root. This gives any AI agent (Cursor, Codex, Copilot, Windsurf, etc.) permanent context about this specific project.

```markdown
# <Project Name>

## Identity
- **Stack**: NestJS 11, Fastify, Zod + nestjs-zod, Swagger, TypeScript, Jest
- **Scaffolded from**: templateCentral nestjs-scaffold skill
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
- **Testing**: New or changed controllers/services/repositories must include Jest tests in the same change (`pnpm test`; e2e when appropriate)

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Update the Identity section with the actual project name and creation date.

### 7. Generate Project CLAUDE.md (MANDATORY for Claude Code users)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Follow **Scaffold: CLAUDE.md (Claude Code only)** in repository root `AGENTS.md`. Write a **short** `CLAUDE.md` (architecture/conventions live in `AGENTS.md` only).

**Build & Dev** (verified commands), e.g.: `pnpm start:dev`, `pnpm build`, `pnpm test`, `pnpm test:e2e`, `pnpm lint`.

**templateCentral skills**: `nestjs-scaffold` (done), `nestjs-add-module`, `nestjs-add-auth`, `nestjs-add-database`, `nestjs-add-integration`, `nestjs-add-test`. **Workflow**: simple/medium → templateCentral skills; complex → Superpowers — root `AGENTS.md`. **Never** secrets in `CLAUDE.md`.

### 8. Task Management (Optional)

Ask whether the user wants structured task management for complex features. If **yes**, append **Option A** or **Option B** from **Scaffold: optional Task Management** in repository root `AGENTS.md` (templateCentral). If **no**, skip.

### 9. Remove Example Code (Optional)

Once the project is verified, use the `shared-remove-example` skill.

NestJS-specific steps (the skill covers these):
- Delete `src/modules/example/` directory
- Remove `ExampleModule` import and reference from `src/modules/index.ts`
- Remove `ExampleModule` from `imports` array in `src/app.module.ts`
- Delete `test/modules/example.controller.spec.ts`

## Rules

- Always update `package.json` name before installing dependencies
- Always copy `.env.example` to `.env` before first run — **never** commit real secrets or paste JWT/DB credentials into `AGENTS.md` / `CLAUDE.md`
- Global pipes and filters go in `app.module.ts`; auth guards at controller/route level (not global, so health checks remain unprotected)
- Verify the API starts and Swagger docs at `/docs` render before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/`, `dist/`, or `.env` when scaffolding
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove the `base/` module — it provides the health check endpoint
- NEVER install packages globally — always use pnpm/npm within the project
- NEVER remove `test/` directory structure when cleaning up example code

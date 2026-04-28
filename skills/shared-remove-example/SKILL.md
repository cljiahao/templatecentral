---
name: shared-remove-example
description: Use when the user wants to remove the example/demo code from a scaffolded project to start with a clean slate.
---

# Remove Example Code

Per-stack cleanup steps for removing the example/demo code from a templateCentral-scaffolded project.

## Next.js

### Files to Delete

- `src/features/example/` (entire directory)

### Imports to Remove

- `src/app/dashboard/(overview)/page.tsx` — remove `ExampleList` import and usage; replace with your own content

### Routes

The dashboard page (`/dashboard`) remains — just replace its content.

### Cleanup Checklist

1. Delete `src/features/example/`
2. Edit `src/app/dashboard/(overview)/page.tsx` — remove example imports, replace grid with placeholder
3. Verify no remaining imports reference `@/features/example`

## Vite + React

### Files to Delete

- `src/features/example/` (entire directory)

### Imports to Remove

- `src/pages/dashboard.tsx` — remove example imports and usage

### Routes

The dashboard page (`/dashboard`) remains — just replace its content.

### Cleanup Checklist

1. Delete `src/features/example/`
2. Edit `src/pages/dashboard.tsx` — remove example imports, replace with placeholder
3. Verify no remaining imports reference `@/features/example`

## FastAPI

### Files to Delete

- `src/api/routers/example.py`
- `src/api/schemas/request/example.py`
- `src/api/schemas/response/example.py`
- `src/api/services/example.py`
- `test/test_api/test_example.py`

### Imports to Remove

- `src/api/routes.py` — remove `from api.routers import example` and `router.include_router(example.router)`

### Cleanup Checklist

1. Delete the files listed above
2. Edit `src/api/routes.py` — remove example router registration
3. Edit `src/api/tags.py` — remove the `EXAMPLE` entry from `APITags` (keep `MISC` and `INFRASTRUCTURE`)
4. Verify no remaining imports reference example modules

## NestJS

### Files to Delete

- `src/modules/example/` (entire directory)
- `test/modules/example.controller.spec.ts`

### Imports to Remove

- `src/modules/index.ts` — remove `export * from './example/example.module'`
- `src/app.module.ts` — remove `ExampleModule` from both the `import` statement at the top of the file and the `@Module({ imports: [...] })` array

### Cleanup Checklist

1. Delete `src/modules/example/` and `test/modules/example.controller.spec.ts`
2. Edit `src/modules/index.ts` — remove export
3. Edit `src/app.module.ts` — remove `ExampleModule` from both the `import` statement and the `@Module({ imports })` array
4. Verify no remaining imports reference example module
5. Run `pnpm test` to confirm no broken test imports

## Rules

- Always verify with a search (grep for `example` or `Example`) after cleanup — stale imports cause build failures.
- The example code is intentionally simple — it exists to demonstrate the architecture patterns, not as production code.
- After cleanup, run that stack’s **tests and production build** (see repository root `AGENTS.md` → Scaffold verification) — the app must still compile and run with no errors.

<!-- ref: cleanup/remove-example/implementation.md
     loaded-by: cleanup/SKILL.md
     prereq: Removing example code. Do not invoke this file directly — it is loaded at runtime by the templatecentral:cleanup skill. -->

# Remove Example Code

Per-stack cleanup steps for removing the example/demo code from a templateCentral-scaffolded project.

## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → note the detected stack from the marker (nextjs / vite-react / fastapi /
nestjs) and proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Verify the example code exists for the detected stack:

| Stack | What to check |
|---|---|
| `nextjs` | `src/features/example/` directory exists |
| `vite-react` | `src/features/example/` directory exists |
| `fastapi` | `src/api/routers/example.py` file exists |
| `nestjs` | `src/modules/example/` directory exists |

If the check fails → ⛔ STOP. Tell the user: "No example code found —
nothing to remove. The example may have already been removed."

If found → proceed to the section for your detected stack below.

## Next.js

### Files to Delete

- `src/features/example/` (entire directory)

### Imports to Remove

- `src/app/dashboard/(overview)/page.tsx` — remove `ExampleList` import and usage; replace with your own content

### Routes

The dashboard page (`/dashboard`) remains — just replace its content.

### Cleanup Checklist

1. Delete `src/features/example/`
2. Edit `src/app/dashboard/(overview)/page.tsx` — remove `ExampleList` import and usage, replace with placeholder content
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

> **Note:** `src/features/auth/` is intentional scaffold code (auth context, `AuthProvider`, `ProtectedRoute`, `LoginCard`) — do **not** delete it. If you have run `vite-react-add-auth` you may replace the dev stub with the real backend implementation; otherwise leave it as-is.

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
- After cleanup, run that stack's **tests and production build** (see repository root `AGENTS.md` → Scaffold verification) — the app must still compile and run with no errors.
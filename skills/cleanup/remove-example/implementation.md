<!-- ref: cleanup/remove-example/implementation.md
     loaded-by: cleanup/SKILL.md
     prereq: Removing example code. Do not invoke this file directly — it is catted by agents via skills/cleanup/SKILL.md (de-registered agent utility). -->

# Remove Example Code

Remove the example/demo code from a templateCentral-scaffolded project.

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → note the detected stack from the marker (nextjs / vite-react / fastapi /
nestjs) and proceed to context check below.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
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

1. Delete `src/features/example/`
2. Edit `src/app/dashboard/(overview)/page.tsx` — remove the `ExampleList` import and usage; the `/dashboard` route stays, with placeholder content
3. Verify no remaining imports reference `@/features/example`

> `src/features/auth/` is intentional scaffold code (auth hooks, `AuthProvider`) — do **not** delete it. `templatecentral:add (auth)` replaces the dev stub with a real implementation.

## Vite + React

1. Delete `src/features/example/`
2. Edit `src/pages/dashboard.tsx` — remove the `ExampleList` import and usage; the `/dashboard` route stays, with placeholder content
3. Verify no remaining imports reference `@/features/example`

> `src/features/auth/` is intentional scaffold code (auth context, `AuthProvider`, `ProtectedRoute`, `LoginCard`) — do **not** delete it. `templatecentral:add (auth)` replaces the dev stub with a real implementation.

## FastAPI

1. Delete `src/api/routers/example.py`, `src/api/schemas/request/example.py`, `src/api/schemas/response/example.py`, `src/api/services/example.py`, `test/test_api/test_example.py`
2. Edit `src/api/routes.py` — remove `from api.routers import example` and its `include_router(example.router, ...)` line
3. Edit `src/api/tags.py` — remove `EXAMPLE` from `APITags` (keep `MISC` and `INFRASTRUCTURE`)
4. Verify no remaining imports reference example modules

## NestJS

1. Delete `src/modules/example/` and `test/modules/example.controller.spec.ts`
2. Edit `src/modules/index.ts` — remove `export * from './example/example.module'`
3. Edit `src/app.module.ts` — remove `ExampleModule` from both the top-level `import` and the `@Module({ imports: [...] })` array
4. Verify no remaining imports reference the example module

## Rules

- Always verify with a search (grep for `example` or `Example`) after cleanup — stale imports cause build failures.
- After cleanup, run that stack's **tests and production build** — `pnpm test` + `pnpm build` for the TypeScript stacks, `python -m pytest` + a container build for FastAPI — the app must still compile and run with no errors.
- Deleting the example directory removes its own `README.md` too, but the **parent** folder's `README.md` (e.g. `src/features/README.md`) still lists `example/` in its `Contents` section — refresh it:
  ```bash
  cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
  ```
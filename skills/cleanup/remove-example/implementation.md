<!-- ref: cleanup/remove-example/implementation.md
     loaded-by: cleanup/SKILL.md
     prereq: Removing example code. Do not invoke this file directly — it is catted by agents via skills/cleanup/SKILL.md (de-registered agent utility). -->

# Remove Example Code

Remove the example/demo code from a templateCentral-scaffolded project.

Needs the `<!-- templateCentral:` marker in `AGENTS.md` (it names the stack); without it, run `templatecentral:migrate` first and stop if still absent. Verify the example code exists for that stack; if not, stop and tell the user: "No example code found — nothing to remove. The example may have already been removed."

| Stack | Example code |
|---|---|
| `nextjs`, `vite-react` | `src/features/example/` |
| `fastapi` | `src/api/routers/example.py` |
| `nestjs` | `src/modules/example/` |

## Next.js

1. Delete `src/features/example/`
2. Edit `src/app/dashboard/(overview)/page.tsx` — remove the `ExampleList` import and usage; the `/dashboard` route stays, with placeholder content

## Vite + React

1. Delete `src/features/example/`
2. Edit `src/pages/dashboard.tsx` — remove the `ExampleList` import and usage; the `/dashboard` route stays, with placeholder content

> `src/features/auth/` is intentional scaffold code (auth context, `AuthProvider`, `ProtectedRoute`, `LoginCard`) — do **not** delete it. `templatecentral:add (auth)` replaces the dev stub with a real implementation.

## FastAPI

1. Delete `src/api/routers/example.py`, `src/api/schemas/request/example.py`, `src/api/schemas/response/example.py`, `src/api/services/example.py`, `test/test_api/test_example.py`
2. Edit `src/api/routes.py` — remove `from api.routers import example` and its `include_router(example.router, ...)` line
3. Edit `src/api/tags.py` — remove `EXAMPLE` from `APITags` (keep `MISC` and `INFRASTRUCTURE`)

## NestJS

1. Delete `src/modules/example/`; in `test/app.e2e-spec.ts` delete the three example-module tests (invalid body, create/read/update/delete, OpenAPI document) and their `@nestjs/swagger` and `nestjs-zod` imports
2. Edit `src/modules/index.ts` — remove `export * from './example/example.module'`
3. Edit `src/app.module.ts` — remove `ExampleModule` from both the top-level `import` and the `@Module({ imports: [...] })` array

## Verify

Run that stack's **tests and production build** (`pnpm test` + `pnpm build`; FastAPI: `python -m pytest` + a container build); the typecheck catches stale imports. Then run `bash scripts/check-docs.sh`: it reports each link or path in the README, AGENTS.md or `docs/` that still points at the example, with file and line. Fix each one.

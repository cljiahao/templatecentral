# Architecture

Codemap. Update it in the same change that moves a layer or a shared module.

## Layers

| Layer | Owns |
|-------|------|
| `src/pages/` | One component per route. Composes features; holds no business logic. |
| `src/router.tsx` | Route definitions. |
| `src/features/<name>/` | One feature: its API calls, components, hooks and schemas. Public entry is the feature `index.ts`. |
| `src/components/` | UI shared by features: app shell in `src/components/layout/`, composed pieces in `src/components/widgets/`. |
| `src/lib/` | HTTP client, constants, errors, small utilities. |

## Dependency direction

`pages` → `features` → `components`, `lib`. Features reach another feature only through its entry point. `lib` imports from no other layer. Nothing imports from `pages`; the app shell in `components/layout` may import features through their entry point.

## Reuse

Search these places before creating a new helper.

| Need | Look in |
|------|---------|
| Shared UI | `src/components/widgets/`, `src/components/layout/` |
| Hooks | `src/hooks/` |
| Utilities | `src/lib/utils/` |
| API client | `src/lib/clients/` |
| Validation | `src/features/<name>/schemas/` (Zod) |
| Error handling and logging | `src/lib/errors/` |
| Constants and env | `src/lib/constants/` |

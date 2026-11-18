# Architecture

Codemap. Update it in the same change that moves a layer or a shared module.

## Layers

| Layer | Owns |
|-------|------|
| `src/app/` | Routes, layouts, route handlers. Composes features; holds no business logic. |
| `src/features/<name>/` | One feature: its API calls, components, hooks and schemas. Public entry is the feature `index.ts`. |
| `src/components/` | UI shared by features: app shell in `src/components/layout/`, composed pieces in `src/components/widgets/`. |
| `src/integrations/` | Clients for external services. |
| `src/lib/` | Constants, errors, logging, security headers, small utilities. |
| `src/proxy.ts` | Request-level protection applied to every response. |

## Dependency direction

`app` → `features` → `components`, `integrations`, `lib`. Features reach another feature only through its entry point. `lib` imports from no other layer. Nothing imports from `app`.

## Reuse

Search these places before creating a new helper.

| Need | Look in |
|------|---------|
| Shared UI | `src/components/widgets/`, `src/components/layout/` |
| Hooks | `src/hooks/` |
| Utilities | `src/lib/utils/` |
| API client | `src/integrations/clients/base/` |
| Validation | `src/features/<name>/schemas/` (Zod) |
| Error handling | `src/lib/errors/` |
| Logging | `src/lib/logger.ts`, `src/lib/utils/with-logging.ts` |
| Constants and env | `src/lib/constants/` |

# Architecture

Codemap. Update it in the same change that moves a layer or a shared module.

## Layers

| Layer | Owns |
|-------|------|
| `src/modules/<feature>/` | One feature: controller, service, repository, DTOs and types. |
| `src/common/` | Constants, exception filters and utilities shared by modules. |
| `src/config/` | Environment parsing and app setup (security, Swagger). |
| `src/bootstrap.ts` | Application start-up wiring. |

## Dependency direction

Controller → service → repository. A module reaches another module only through its `*.service` or `*.module` file. `common` and `config` import from no module. Nothing imports from a controller.

## Reuse

Search these places before creating a new helper.

| Need | Look in |
|------|---------|
| Utilities | `src/common/utils/` |
| Validation | the `*.dto.ts` file of the module (nestjs-zod) |
| Error handling | `src/common/filters/` |
| Constants | `src/common/constants/` |
| Config and env | `src/config/` |
| Logging and HTTP client | none yet; `templatecentral:add` creates them in `src/common/` or `src/modules/` |

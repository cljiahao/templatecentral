# Logging Integration Design

**Date:** 2026-04-27  
**Scope:** templateCentral — NestJS, Next.js, FastAPI templates + new `shared/add-logging` skill

---

## Summary

Add `pino` (NestJS, Next.js) and confirm `python-json-logger` (FastAPI) as mandatory structured logging libraries. Create `shared/add-logging` skill that asks one question about logging tier, then wires up all logging for that tier and all tiers below it.

---

## Decisions

| Template | Library | Status |
|---|---|---|
| FastAPI | `python-json-logger` | Already done — no changes |
| NestJS | `nestjs-pino` + `pino-http` + `pino-pretty` (dev) | Add |
| Next.js | `pino` + `pino-pretty` (dev) | Add |
| Vite-React | None | Skip — frontend only |

---

## Template Changes

### FastAPI
No changes. `python-json-logger>=3.3.0` already in `src/requirements.txt`. Full setup exists in `core/logging.py` and `core/json/logging.json` with JSON formatters, rotating file handlers, and per-environment profiles (`dev`/`uat`/`prod`).

### NestJS

**Dependencies to add (`package.json`):**
```json
"nestjs-pino": "^4.x",
"pino-http": "^10.x"
```
```json
"pino-pretty": "^13.x"  // devDependencies
```

**Changes to `src/main.ts`:**
- Remove `ConsoleLogger` instantiation
- Import and register `LoggerModule` from `nestjs-pino` in bootstrap
- Configure pino: JSON in `uat`/`prod`, pretty in `dev`
- All existing `new Logger('X')` calls remain unchanged — `nestjs-pino` hooks into NestJS Logger interface

### Next.js

**Dependencies to add (`package.json`):**
```json
"pino": "^9.x"
```
```json
"pino-pretty": "^13.x"  // devDependencies
```

**New file: `src/lib/logger.ts`**
- Exports singleton pino instance
- JSON transport in `production`, pretty transport in `development`
- Log level driven by `LOG_LEVEL` env var (default `info`)

**New file: `src/lib/utils/with-logging.ts`**
- HOF wrapping Next.js App Router route handlers
- Logs at Tier 1: `method`, `path`, `status_code`, `duration_ms`, `user_id` (if present)
- Usage: `export const GET = withLogging(handler)`

**Updated: `src/lib/errors/error-log-handler.ts`**
- Replace `console.error` with pino logger calls
- `logError()` now emits structured JSON: `{ label, error_type, message, status_code }`

---

## Logging Tier Taxonomy

Tiers are cumulative: Tier 3 includes Tier 2 which includes Tier 1.

### Tier 1 — Base (always included)
| Event | Fields |
|---|---|
| Endpoint request/response | `method`, `path`, `status_code`, `duration_ms`, `user_id` |
| Unhandled exceptions | `path`, `error`, full stack trace |
| App startup / shutdown | `port`, `environment` |

### Tier 2 — Standard (default)
All of Tier 1, plus:

| Event | Fields |
|---|---|
| Auth: login success | `user_id`, `method` (password/oauth) |
| Auth: login failure | `reason`, `ip` (no password) |
| Auth: logout | `user_id` |
| Auth: token refresh | `user_id` |
| Auth: access denied | `user_id`, `path`, `required_role` |
| Outbound HTTP calls | `method`, `url` (no query secrets), `status_code`, `duration_ms` |
| Key domain events | Predefined locations in service layer per stack |

### Tier 3 — Verbose
All of Tier 1 + Tier 2, plus:

| Event | Fields |
|---|---|
| Slow DB queries | `query_name`, `duration_ms` (threshold: >500ms), no full SQL text |
| Sanitized request context | `method`, `path`, `headers` (auth header redacted), no body |
| Cache hits/misses | `cache_key`, `hit` (boolean) |

---

## Hardcoded Prohibitions (not configurable by tier)

The skill must never add log calls that capture:
- Passwords, tokens, API keys, secrets
- PII: email, name, phone, address (raw)
- Full request or response bodies
- Credit card numbers or financial identifiers
- SQL query text (only query name / label)

These apply regardless of tier selection.

---

## `shared/add-logging` Skill

**Location:** `claude-skills/shared/add-logging/SKILL.md`

**Trigger:** When setting up logging in any templateCentral project.

**Flow:**

1. Ask one question:
   > "Logging tier? 1=Base / **2=Standard** (default) / 3=Verbose"

2. Apply selected tier + all tiers below it — no further questions.

3. Detect stack from project structure:
   - `nest-cli.json` present → NestJS
   - `next.config.ts` present → Next.js
   - `pyproject.toml` + FastAPI import → FastAPI

4. Wire up all log calls for the selected tier across the stack.

**Stack-specific wiring locations:**

| Stack | Tier 1 | Tier 2 additions | Tier 3 additions |
|---|---|---|---|
| FastAPI | `core/logging.py` already handles; add request middleware if missing | Auth handlers in `api/routers/`, HTTP client in `utils/` | Slow query hook, request context middleware |
| NestJS | pino-http via `LoggerModule` (automatic) | Auth guard/filter, `HttpService` interceptor, service methods | DB query interceptor, request serializer |
| Next.js | `withLogging` HOF on route handlers | Auth callbacks in `auth.ts`, fetch client in `integrations/` | Request context logger, cache instrumentation |

---

## Environment Variables

All stacks expose:
- `LOG_LEVEL` — overrides default level (`debug`/`info`/`warn`/`error`). Default: `info`.

---

## What Is Not In Scope

- Log aggregation / shipping (DataDog, Loki, CloudWatch) — separate concern
- Log sampling or rate limiting
- Vite-React — no server, no logging library
- Changing FastAPI's existing logging infrastructure

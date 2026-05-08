---
name: shared-add-logging
description: Use to wire structured, JSON-formatted logging into any templateCentral project — covers three cumulative tiers (base, standard, verbose), per-stack wiring locations, and a hardcoded prohibition list for sensitive data.
---

# Add Structured Logging

Wire structured JSON logging into your project at the right level of detail. All stacks emit machine-readable logs with consistent field names. Sensitive data is never logged, regardless of tier.

## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## When to Use

- Setting up logging from scratch after scaffolding a new project
- Upgrading from `console.log` / `print` statements to structured logging
- Adding auth event tracking, outbound HTTP observability, or slow-query detection
- Reviewing logging coverage before a production deployment

## First: One Question

Before writing any code, ask the user:

> **What logging tier do you need?**
> - **Tier 1 — Base**: Endpoint request/response, unhandled exceptions, app startup/shutdown
> - **Tier 2 — Standard** *(default)*: Tier 1 + auth events, outbound HTTP calls, key domain events
> - **Tier 3 — Verbose**: Tier 1 + 2 + slow DB queries (>500 ms), sanitized request context, cache hits/misses
>
> Press Enter to accept Tier 2, or type 1 or 3.

Do not ask any other questions. Implement the chosen tier (and all lower tiers, since tiers are cumulative).

## Hardcoded Prohibitions — Never Log These

Regardless of tier, environment, or log level, these fields **must never appear** in log output:

- **Passwords** — in any form (plain or hashed)
- **Tokens** — access tokens, refresh tokens, JWTs, session tokens, CSRF tokens
- **API keys and secrets** — third-party credentials, signing keys, webhook secrets
- **PII (raw)** — email address, full name, phone number, postal address
- **Full request or response bodies** — log field names and counts at most, never raw content
- **Credit card numbers or financial identifiers** — PAN, CVV, bank account numbers
- **SQL query text** — log only the query name or label, never the SQL string or bound parameters
- **Authorization header value** — log `auth_present: true/false` only; never the header value

## Tiers (Cumulative)

Each tier adds to all lower tiers. Implementing Tier 3 means implementing Tier 1 + Tier 2 + Tier 3.

### Tier 1 — Base (always included)

| Event | Required fields |
|-------|----------------|
| Endpoint request/response | `method`, `path`, `status_code`, `duration_ms` |
| Unhandled exception | `path`, `error` (message only), full stack trace (server-side only) |
| App startup | `port`, `environment` |
| App shutdown | `environment` |

### Tier 2 — Standard (default; includes Tier 1)

| Event | Required fields |
|-------|----------------|
| Login success | `user_id`, `method` (e.g. `"password"`, `"oauth"`) |
| Login failure | `reason`, `ip` — **no password** |
| Logout | `user_id` |
| Token refresh | `user_id` |
| Access denied | `user_id`, `path`, `required_role` |
| Outbound HTTP call | `method`, `url` (sanitized — strip query secrets), `status_code`, `duration_ms` |
| Key domain events | One log call per service method that causes a significant state change |

### Tier 3 — Verbose (includes Tier 1 + Tier 2)

| Event | Required fields |
|-------|----------------|
| Slow DB query (>500 ms) | `query_name`, `duration_ms` — **no SQL text** |
| Sanitized request context | `method`, `path`, headers presence only (`auth_present: true/false`) |
| Cache hit/miss | `cache_key`, `hit` (boolean) |

## Environment Variable

Log level is configured per stack:

- **NestJS**: reads `LOG_LEVEL` env var (default: `info`). Valid values: `trace`, `debug`, `info`, `warn`, `error`, `fatal`. Set in `.env`: `LOG_LEVEL=info`
- **Next.js**: reads `LOG_LEVEL` env var (default: `info`). Valid values: `trace`, `debug`, `info`, `warn`, `error`, `fatal`. Set in `.env.local`: `LOG_LEVEL=info`
- **FastAPI**: log level is configured per-environment in `src/core/json/logging.json` (`dev`=DEBUG, `uat`/`prod`=INFO). No `LOG_LEVEL` env var — the `ENVIRONMENT` variable selects the log level profile.

---

## Implementation

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to the stack-specific implementation below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to the stack-specific implementation below.
- Still absent (user chose to stop) → exit. Do not generate any files.

## Stack Implementation

Run the matching stack guide:

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-logging/nextjs.md"
```
Follow the loaded guide exactly.

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-logging/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-logging/nestjs.md"
```
Follow the loaded guide exactly.

> Note: Logging is backend-only — no Vite + React section.

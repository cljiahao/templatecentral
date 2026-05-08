---
name: shared-add-error-handling
description: Use to add consistent error handling and response schemas across all stacks — covers unified error responses, security boundaries, logging integration, and per-stack implementation patterns.
---

# Add Error Handling & Boundaries

Implement consistent, secure error handling across your stack. All errors return a unified response schema with appropriate HTTP status codes. Errors are logged server-side with context; sensitive details are never exposed to clients in production.

## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## When to Use

- Adding a new API route or endpoint that needs error handling
- Enhancing existing error handling to be more consistent or secure
- Integrating logging with error responses
- Setting up error boundary components for client-side error UI

## Security Checklist

- [ ] **Stack traces never exposed** — Production responses exclude file paths, line numbers, and internal error chains
- [ ] **Sensitive fields protected** — No API keys, tokens, database URLs, or internal identifiers in error responses
- [ ] **Field-level validation errors only** — User-facing 400 errors include field names and messages, never raw query/filter values
- [ ] **SQL injection prevention** — No user input echoed in error messages; Zod/Pydantic validates before ORM parameterization
- [ ] **Path traversal prevention** — File validation errors check `../` patterns; never log raw file paths from user input
- [ ] **Auth bypass prevention** — 401/403 responses do not reveal whether resource exists; "Not found" for both missing and unauthorized resources
- [ ] **Rate limit headers included** — 429 responses include `Retry-After` header; no stack traces
- [ ] **Unhandled exceptions caught globally (OWASP A10:2025)** — No raw exception objects returned; all errors go through unified handler. Stack traces and internal messages surfacing to clients are an A10:2025 violation — log full detail server-side only, return generic messages to clients
- [ ] **Logging excludes request bodies** — Never log raw `request.json()` or form data; log only status, path, duration, user ID
- [ ] **Environment-based detail levels** — Development: include stack traces; Production: generic messages only

## Unified Error Response Schema

All errors return this shape (regardless of stack):

**Success response:** (status 200, 201, etc.)
```json
{
  "data": { /* actual response */ }
}
```

**Error response:** (status 400, 401, 404, 500, etc.)
```json
{
  "error": "User-facing error message",
  "details": {
    "fieldErrors": {
      "email": ["Must be a valid email"],
      "password": ["Minimum 8 characters"]
    },
    "code": "VALIDATION_ERROR"
  }
}
```

**Schema breakdown:**
- `error` — Human-readable, user-facing message (always present)
- `details` — Optional object with:
  - `fieldErrors` — Object mapping field names to error arrays (for validation errors only)
  - `code` — Machine-readable error code (e.g., `NOT_FOUND`, `UNAUTHORIZED`, `RATE_LIMIT_EXCEEDED`)

**HTTP Status Codes:**
- **400 Bad Request** — Validation failed, malformed JSON, missing required fields
- **401 Unauthorized** — No authentication, invalid credentials, expired token
- **403 Forbidden** — Authenticated but lacks permission for this resource
- **404 Not Found** — Resource doesn't exist (also used for unauthorized resource access)
- **408 Request Timeout** — Request took too long
- **409 Conflict** — Resource already exists, state conflict, constraint violation
- **429 Too Many Requests** — Rate limited; include `Retry-After` header
- **500 Internal Server Error** — Unhandled exception, database error, external service failure
- **502/503 Bad Gateway/Service Unavailable** — External dependency down

## Rules

1. **All user input must be validated before use** — Never trust raw `request.json()`, `request.params`, or `request.query`
2. **Validation errors must be field-level** — Map Zod/Pydantic errors to field names, not raw validation paths
3. **Custom exceptions allowed** — Raise domain-specific exceptions (e.g., `NotFoundError`, `ValidationError`); catch once in global handler
4. **Rate-limit 429 errors must include Retry-After header** — Enables smart client-side backoff
5. **Errors must be logged server-side** — Include requestId, userId, method, path, statusCode, duration; exclude request bodies and sensitive fields
6. **Production never exposes stack traces** — Check `NODE_ENV`, `ENVIRONMENT`, or Python `DEBUG` setting
7. **Unhandled exceptions must be caught globally** — Every stack has a catch-all handler that logs and returns 500
8. **Client receives generic 500 messages** — Detailed error information stays in server logs only
9. **404 for both missing and unauthorized resources** — Never reveal whether a resource exists if user lacks access

## Step 0 — Verify context

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
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/nextjs.md"
```
Follow the loaded guide exactly.

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/nestjs.md"
```
Follow the loaded guide exactly.

**Vite + React:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/vite-react.md"
```
Follow the loaded guide exactly.

---
name: shared-validation-patterns
description: Add consistent input validation with Zod/Pydantic, OWASP/CWE compliance, and sanitization across stacks
---

# Validation Patterns & Sanitization

Implement consistent input validation at all entry points: form submissions, API endpoints, query parameters, file uploads, and external API responses. Use Zod (TypeScript) or Pydantic (Python) to enforce type safety and prevent common vulnerabilities (SQL injection, XSS, path traversal).

## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## When to Use

- Creating forms with client and server validation
- Building API endpoints that accept user input
- Validating query parameters, path parameters, or file uploads
- Consuming external APIs and validating responses
- Ensuring OWASP/CWE compliance (SQL injection, XSS, path traversal)

## Security Checklist

- [ ] **CWE-89 (SQL Injection)** — Use ORM parameterization or prepared statements; never concatenate user input into queries
- [ ] **CWE-79 (XSS)** — React JSX auto-escapes; Zod/Pydantic validates types; never use `dangerouslySetInnerHTML` with user input
- [ ] **CWE-22 (Path Traversal)** — Reject filenames with `../` or `/`, validate against whitelist, never use user input directly in `fs.readFile()`
- [ ] **CWE-352 (CSRF)** — Framework-handled by SameSite cookies and CSRF tokens; validate origin headers
- [ ] **CWE-287 (Auth Bypass)** — Route/controller-level auth checks before processing user input; never skip auth in business logic
- [ ] **CWE-434 (File Upload)** — Validate file type (whitelist), size, reject suspicious extensions (`.exe`, `.sh`)
- [ ] **CWE-400 (Uncontrolled Resource)** — Rate limit uploads, reject excessive nesting in JSON, enforce max request body size
- [ ] **Validation happens before use** — Parse with Zod/Pydantic before passing to ORM, service layer, or filesystem
- [ ] **Error messages are field-level** — Never echo raw user input; use schema error paths
- [ ] **Server revalidates client validation** — Client-side is UX only; server must always validate independently

## Pattern Library

Load the Zod/Pydantic pattern reference before using any stack section:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/patterns.md"
```
Reference these patterns throughout the implementation steps below.

## Implementation

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to the Stack Implementation section below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to the Stack Implementation section below.
- Still absent (user chose to stop) → exit. Do not generate any files.

## Stack Implementation

Then run the matching stack guide:

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/nextjs.md"
```
Follow the loaded guide exactly.

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/nestjs.md"
```
Follow the loaded guide exactly.

**Vite + React:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/vite-react.md"
```
Follow the loaded guide exactly.

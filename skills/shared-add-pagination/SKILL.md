---
name: shared-add-pagination
description: Use when building list endpoints with multiple pages — covers offset-based pagination, response envelopes, CWE-400 resource exhaustion prevention, and per-stack implementations.
---

# Add Pagination & Filtering

Implement consistent pagination across your stack. All list endpoints return paginated responses with metadata. Pagination prevents resource exhaustion (CWE-400) by enforcing limits and defaults.

## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## When to Use

- Building API endpoints that return lists (projects, users, products, etc.)
- Adding page/limit query parameters to existing list endpoints
- Implementing "next/previous" navigation in UI
- Preventing unbounded queries that could consume database resources

## Security Checklist

- [ ] **Max limit enforced** — Query enforces maximum results per page (e.g., max 100 items)
- [ ] **Default limit applied** — Missing `limit` parameter uses safe default (e.g., 10-20 items)
- [ ] **Sort field validated** — Sort column comes from a whitelist, never raw user input
- [ ] **Negative page/limit rejected** — Page < 1 and limit < 1 return 400 error
- [ ] **Page calculation correct** — Offset calculated as `(page - 1) * limit`, no off-by-one errors
- [ ] **Total count bounded** — Total count does not require O(n) database scan (use index or estimate)
- [ ] **Pagination metadata included** — Every list response includes page, limit, total, hasMore

## Unified Pagination Response Schema

All list endpoints return this shape (matches Phase 1 `shared-add-error-handling` format):

**Success response:** (status 200)
```json
{
  "data": {
    "items": [
      { "id": "1", "name": "Project A" },
      { "id": "2", "name": "Project B" }
    ],
    "pagination": {
      "page": 1,
      "limit": 10,
      "total": 247,
      "hasMore": true
    }
  }
}
```

**Schema breakdown:**
- `data` — Wrapper object containing:
  - `items` — Array of list items (projects, users, etc.)
  - `pagination` — Object with:
    - `page` — Current page number (1-indexed)
    - `limit` — Number of items per page
    - `total` — Total count of items (may be approximate for performance)
    - `hasMore` — Boolean: true if more pages exist after this one

**Error response:** (status 400, 422, etc.) — See `shared-add-error-handling`
```json
{
  "error": "Invalid query parameters",
  "details": {
    "fieldErrors": {
      "page": ["Must be 1 or greater"],
      "limit": ["Must be between 1 and 100"]
    }
  }
}
```

## Rules

1. **All pagination params must be validated** — Use Zod (TypeScript) or Pydantic (Python) schema from `shared-validation-patterns`
2. **Limit must have a maximum** — Enforce max (e.g., max 100 items per request)
3. **Default limit must be reasonable** — If omitted, use sensible default (10-20 items)
4. **Sort field must be from a whitelist** — Never allow user input directly in ORDER BY; validate against allowed fields
5. **Offset calculated correctly** — Use `(page - 1) * limit` formula consistently
6. **Pagination metadata included** — Every list response must include page, limit, total, hasMore
7. **Database indexes required** — Sort and filter fields must be indexed for performance
8. **Total count careful** — For large tables, consider approximate count or bounded estimation (no full table scans)

## Implementation

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm the project contains at least one route handler file
(e.g. any `.ts` file under `src/app/api/` for Next.js, any `.py` file under
`src/api/routers/` for FastAPI, any controller file under `src/modules/` for NestJS,
or any `.ts` file under `src/features/*/api/` for Vite + React).

If none found → ⛔ STOP. Tell the user: "No API routes or endpoints found. Add some
first, then return here to add pagination."

If found → proceed to the stack-specific implementation below.

## Stack Implementation

Run the matching stack guide:

**Next.js:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/nextjs.md"
```
Follow the loaded guide exactly.

**FastAPI:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/fastapi.md"
```
Follow the loaded guide exactly.

**NestJS:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/nestjs.md"
```
Follow the loaded guide exactly.

**Vite + React:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/vite-react.md"
```
Follow the loaded guide exactly.

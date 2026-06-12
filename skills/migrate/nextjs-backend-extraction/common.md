<!-- ref: migrate/nextjs-backend-extraction/common.md
     loaded-by: migrate/nextjs-backend-extraction/fastapi.md + migrate/nextjs-backend-extraction/nestjs.md → migrate/SKILL.md
     prereq: Shared phases for Next.js backend extraction. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Next.js Backend Extraction — Shared Phases

Read this file alongside the target-specific leaf (fastapi.md or nestjs.md). Phases execute in numeric order: 1, 2, [3–7 from leaf], 8, 9, 10.

Variable values by target:
| Variable | FastAPI | NestJS |
|---|---|---|
| `[BACKEND]` | FastAPI | NestJS |
| `[DEV_PORT]` | 8000 | 3001 |
| `[CORS_VAR]` | `CORS_ORIGINS` | `CLIENT_URL` |

---

## Phase 1 — Assessment (autonomous)

Scan the Next.js project root. Run each check in order.

**1a. Verify templateCentral marker**

Read `AGENTS.md`. If `<!-- templateCentral: nextjs@` is not on line 1, exit:
> "This skill requires a Next.js project scaffolded with templatecentral:scaffold. No changes made."

**1b. Read project name**

Read `package.json` → `name` field. This becomes `[project-name]`. The [BACKEND] project will be created at `../[project-name]-api`.

**1c. Inventory API routes**

List all `src/app/api/**/route.ts` files. For each, read the exported function names to determine HTTP methods (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`).

**1d. Identify integrations to move**

For each `route.ts` file, scan import statements for any path starting with `@/integrations/` or `../integrations/`. Collect the unique set. See the leaf file for stack-specific base-client handling.

**1e. Identify integrations staying in Next.js**

List all files under `src/integrations/` that were NOT collected in 1d.

**1f. Detect database**

Check for `drizzle.config.ts` (Drizzle) or `src/integrations/database/` containing `.schema.ts` files (Mongoose schemas). Record which ORM if found.

**1g. Detect auth**

Check whether `proxy.ts` or `src/proxy.ts` exists. Record presence.

**Print the assessment:**

```
📋 Backend Extraction Assessment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project:          [project-name]  →  ../[project-name]-api ([BACKEND])

API routes (move to [BACKEND]):
  [list each route.ts with methods, e.g. src/app/api/users/route.ts  GET POST]

Integrations to move (imported by API routes):
  [list each file path]

Integrations staying in Next.js:
  [list each file path, or "None"]

Database:         [see leaf for ORM variants]
Auth:             [✓ proxy.ts detected / None detected]

Next.js after migration: pure frontend, calls NEXT_PUBLIC_API_URL
New backend URL:  http://localhost:[DEV_PORT] (dev) / NEXT_PUBLIC_API_URL (prod)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 2 — Scope Confirmation ⛔ GATE

Do not proceed until the user responds. Ask:

> "This will create `../[project-name]-api` ([BACKEND]), migrate the items listed above, and rewire Next.js as a pure frontend. This cannot be automatically undone. Proceed? (yes / no)"

If yes → before making any changes, ensure a clean tree. If uncommitted changes exist, commit them on the **current** branch (or stash them) — do not switch branches with work in flight:
```bash
git add -A
git diff --cached --quiet || git commit -m "chore: pre-extraction snapshot"
snapshot_commit=$(git rev-parse HEAD)
```
Print the snapshot commit (`$snapshot_commit`) to the user so they can restore it if needed.

If no → print "No changes made." and exit.

---

## Phase 3 — shared skeleton (the leaf adds stack specifics)

Determine the sibling path: `../[project-name]-api`.

Load and follow the [BACKEND] scaffold steps — see the leaf file for the exact `cat` paths (fastapi or nestjs scaffold dirs differ). Work from `../[project-name]-api` as the project root.

**Do not run post-scaffold agents** (build, test, update, review) — verification happens in Phase 10.

---

## Phase 8 — Rewire Next.js Frontend (autonomous)

0. **Rewire auth before deleting routes** (only if auth was detected in Phase 1g) — `src/app/api/` includes the better-auth handler (`src/app/api/auth/[...all]/route.ts`). The Phase 7 backend uses JWT auth, which does not speak the better-auth protocol — re-pointing the better-auth client at it will not work. Before deleting the handler:
   - **Replace** `lib/auth-client.ts` (better-auth client) with a small client that calls the new backend's JWT endpoints (`/auth/login`, `/auth/me`) and update `features/auth/` consumers accordingly
   - Enable CORS credentials on the backend (see leaf file for the stack-specific setting) if using cookie-based sessions
   - If sessions are cookie-based, set auth cookies to `SameSite=None; Secure` for cross-origin (same-site localhost dev may use `Lax`); JWT bearer tokens in the `Authorization` header need no cookie attributes
   - Verify the login flow end-to-end before proceeding

1. **Delete `src/app/api/`** — all route handlers have moved to [BACKEND].

2. **Update `src/lib/constants/env.ts`** — add `API_BASE`:

```typescript
export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:[DEV_PORT]';
```

> Direct client→backend calls require the CORS setup above; alternatively keep the Next.js rewrites proxy model from `templatecentral:standards` (full-stack-pairing).

3. **Update feature service files** — for each file under `src/features/` that calls `fetch('/api/...')`, replace with `API_BASE`:

```typescript
// Before
const res = await fetch('/api/users');

// After
import { API_BASE } from '@/lib/constants/env';
const res = await fetch(`${API_BASE}/users`);
```

4. **Update `.env.example`** — add:

```
# Backend API ([BACKEND])
# Dev default: http://localhost:[DEV_PORT]
NEXT_PUBLIC_API_URL=http://localhost:[DEV_PORT]
```

5. **Update `.env.local`** — add the same line.

6. **Clean up `src/integrations/`** — after Phase 5 cleanup, scan for any remaining entries that are now unused (no imports anywhere in the Next.js codebase). Delete unused files. If the directory is empty, delete it.

---

## Phase 9 — Update Config & Docs (autonomous)

**[BACKEND] project (`../[project-name]-api`):** See the leaf file for the CORS config step — FastAPI uses `CORS_ORIGINS` in `src/.env.default`; NestJS reads `CLIENT_URL` from `src/config/env.config.ts`.

Update `../[project-name]-api/AGENTS.md` — prepend to Project-Specific Notes:
```
- Extracted from `[project-name]` (Next.js frontend) — see `../[project-name]`
- Frontend calls this API; set [CORS_VAR] to the Next.js origin in production
```

**Next.js project:**

Update `AGENTS.md` Architecture Decisions — replace the BFF note with:
```
- API routes removed — backend extracted to `../[project-name]-api` ([BACKEND])
- This project is a pure frontend; all data fetching uses `NEXT_PUBLIC_API_URL`
```

---

## Phase 10 — Verify (autonomous)

Run in sequence. Stop and report the exact error on first failure.

See the leaf file for the exact verify commands (pip+pytest for FastAPI; pnpm for NestJS).

**If all pass**, print:

```
✓ Migration complete.

Next.js frontend: [original-project-path]
  → Pure frontend. Set NEXT_PUBLIC_API_URL in your deployment environment.

[BACKEND] backend:  ../[project-name]-api
  → Set [CORS_VAR] to the Next.js origin in your deployment environment.

Next steps:
- Review proxy.ts — update any hardcoded /api paths to use NEXT_PUBLIC_API_URL
- Set up Docker Compose if you want both services running locally with one command
- Configure CI/CD pipelines for each repo independently
```

**If any command fails**, print the exact error output and stop. Do not continue to the next phase.

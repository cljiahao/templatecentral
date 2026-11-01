<!-- ref: migrate/nextjs-backend-extraction/common.md
     loaded-by: migrate/nextjs-backend-extraction/fastapi.md + migrate/nextjs-backend-extraction/nestjs.md → migrate/SKILL.md
     prereq: Shared phases for Next.js backend extraction. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Next.js Backend Extraction — Shared Phases

Read with the target leaf (fastapi.md or nestjs.md). Phase order: 1, 2, [3–7 from leaf], 8, 9, 10.

Variable values by target:
| Variable | FastAPI | NestJS |
|---|---|---|
| `[BACKEND]` | FastAPI | NestJS |
| `[DEV_PORT]` | 8000 | 3001 |
| `[CORS_VAR]` | `CORS_ORIGINS` | `CLIENT_URL` |

---

## Phase 1 — Assessment (autonomous)

Run each check in order from the Next.js project root.

**1a. Verify templateCentral marker**

Read `AGENTS.md`. If `<!-- templateCentral: nextjs@` is not on line 1, exit:
> "This skill requires a Next.js project scaffolded with templatecentral:scaffold. No changes made."

**1b. Read project name**

`package.json` `name` is `[project-name]`; [BACKEND] goes in `../[project-name]-api`.

**1c. Inventory API routes**

List every `src/app/api/**/route.ts` and its exported HTTP methods (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`).

**1d. Identify integrations to move**

Collect the unique `@/integrations/` or `../integrations/` imports of every `route.ts`. The leaf covers base-client handling.

**1e. Identify integrations staying in Next.js**

List every file under `src/integrations/` not collected in 1d.

**1f. Detect database**

Record the first match (these are the files `templatecentral:add (database)` creates):

| Signal | DB layer |
|---|---|
| `drizzle.config.ts` | Drizzle |
| `src/integrations/database/kysely-client.ts` | Kysely |
| `src/integrations/database/mongoose-client.ts` | Mongoose |

**1g. Detect auth**

Auth is present when `proxy.ts` or `src/proxy.ts` imports from `better-auth` (`getSessionCookie`). A proxy that only calls `applyFrameProtection` (the scaffold default) is not auth.

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

Next.js after migration: pure frontend — browser → /api/external (Next rewrite), server → BACKEND_URL
New backend URL:  BACKEND_URL (server-only; http://localhost:[DEV_PORT] in dev)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 2 — Scope Confirmation ⛔ GATE

Do not proceed until the user responds. Ask:

> "This will create `../[project-name]-api` ([BACKEND]), migrate the items listed above, and rewire Next.js as a pure frontend. This cannot be automatically undone. Proceed? (yes / no)"

If yes → require a clean tree first. If `git status --porcelain` is non-empty, stop and ask the user to commit or stash their work themselves (do not commit on their behalf without an explicit instruction), then re-check. Once clean, record and print the restore point:
```bash
git rev-parse HEAD
```

If no → print "No changes made." and exit.

---

## Phase 3 — shared skeleton (the leaf adds stack specifics)

Follow the [BACKEND] scaffold steps (the leaf gives the `cat` paths) with `../[project-name]-api` as the project root.

**Do not run post-scaffold agents** (build, test, update, review) — verification happens in Phase 10.

---

## Shared rules for leaf Phases 5 and 7

- **Phase 5 cleanup** — delete each moved integration file from Next.js; delete `src/integrations/` only if nothing frontend-only remains.
- **Phase 7 `proxy.ts`** — stays in Next.js, protecting frontend routes. Point hardcoded `/api/auth/...` calls at `process.env.BACKEND_URL`. Phase 8 step 0 swaps its session check.

---

## Phase 8 — Rewire Next.js Frontend (autonomous)

The browser never calls [BACKEND] directly: client components call same-origin `/api/external/*`, which a `rewrites()` entry forwards to `BACKEND_URL`; server components, layouts and `proxy.ts` call the server-only `BACKEND_URL`. There is **no** `NEXT_PUBLIC_*` backend variable. Cookie mode depends on this layout, defined in:
```bash
cat "<skill-dir>/../standards/full-stack-pairing/implementation.md"
```

0. **Rewire auth before deleting routes** (only if Phase 1g detected auth). The Phase 7 backend issues its own JWT and does not speak the better-auth protocol, so before deleting `src/app/api/auth/[...all]/route.ts`:
   - **Enable the backend's cookie mode** ("Browser Client (Cookie Mode)" in the [BACKEND] auth skill): the browser logs in with `POST /api/external/auth/session` and never holds a token. Never go cross-origin with `SameSite=None` or credentialed CORS
   - **Replace** the better-auth client `lib/auth-client.ts` with full-stack-pairing's `backendFetch` (Step 4) calls to `auth/session`, `auth/me` and `auth/logout`; update the `features/auth/` consumers
   - **`proxy.ts`**: drop `getSessionCookie` (it looks for better-auth's cookie name) and use `const hasSession = req.cookies.has('__Host-session') || req.cookies.has('session');`. Add `/api/external/auth/session` and `/api/external/health` as **exact** public paths (full-stack-pairing Step 2 explains why prefixes are unsafe)
   - **Protected layouts**: replace `auth.api.getSession(...)` with full-stack-pairing's `getCurrentUser()` (calls `BACKEND_URL/auth/me` with the cookies) and `redirect(PAGE_ROUTES.LOGIN)` on `null`. Then remove `lib/auth.ts` and the `better-auth` dependency
   - Verify the flow end-to-end before proceeding: login → 204 + `Set-Cookie`, `/dashboard` renders, a non-GET without `X-CSRF-Token` → 403

1. **Delete `src/app/api/`, except `src/app/api/health/route.ts`**: the health route is the Next container's liveness probe (Dockerfile `HEALTHCHECK`, `test/api/health.test.ts`, a public path in `proxy.ts`).

2. **Add the rewrite and the browser path**: put full-stack-pairing Step 2's `rewrites()` entry (destination `${BACKEND_URL}/:path*`) beside `headers()` in `next.config.ts`, and `API_ROUTES.BACKEND` (`/api/external`) beside `HEALTH` in `src/lib/constants/routes.ts`.

3. **Update the callers**. Every `fetch('/api/...')` under `src/features/` changes:

```typescript
// Before
const res = await fetch('/api/users');

// After: client component / hook (same-origin, sends X-CSRF-Token on non-GET)
import { backendFetch } from '@/lib/clients/backend-browser';
const res = await backendFetch('users');

// After: server component / route handler, via getBackendClient() from
// src/integrations/clients/backend-client.ts (full-stack-pairing Step 4; reads BACKEND_URL)
```

4. **Update `.env.example`** with:

```
# Backend API ([BACKEND]) — server-only, never NEXT_PUBLIC_. Needed at BUILD time too:
# the /api/external rewrite is baked into the build output.
BACKEND_URL=http://localhost:[DEV_PORT]
```

5. **`.env.local`**: ask the user to add the same line (agent edits to `.env*` files are hook-blocked by design).

6. **Clean up `src/integrations/`**: delete any remaining entry nothing imports, then the directory if empty. `clients/base/` stays while `backend-client.ts` uses it.

---

## Phase 9 — Update Config & Docs (autonomous)

**[BACKEND] project (`../[project-name]-api`):** apply the leaf file's CORS config step.

Phases 4–7 created folders after the Phase 3 README pass. Re-run the documentation kit over `../[project-name]-api` before Phase 10:
```bash
cd ../[project-name]-api
cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
```

Update `../[project-name]-api/AGENTS.md` — prepend to Project-Specific Notes:
```
- Extracted from `[project-name]` (Next.js frontend) — see `../[project-name]`
- The Next.js frontend reaches this API through its `/api/external` rewrite (same-origin), so it needs no [CORS_VAR] entry
```

**Next.js project:**

Update `AGENTS.md` Architecture Decisions — replace the BFF note with:
```
- API routes removed — backend extracted to `../[project-name]-api` ([BACKEND])
- This project is a pure frontend: the browser calls `/api/external/*` (a rewrite to `BACKEND_URL`), and server code calls `BACKEND_URL` directly. There is no `NEXT_PUBLIC_*` backend URL
```

---

## Phase 10 — Verify (autonomous)

Run in sequence. Stop and report the exact error on first failure.

Use the leaf file's verify commands.

**If all pass**, print:

```
✓ Migration complete.

Next.js frontend: [original-project-path]
  → Pure frontend. Set BACKEND_URL in the build AND runtime environment (rewrites are baked at build).

[BACKEND] backend:  ../[project-name]-api
  → Reached same-origin via the Next.js rewrite. No CORS entry is needed for the frontend.

Next steps:
- Review proxy.ts: it gates /api/external/* before the rewrite forwards it, so keep the backend's public endpoints as exact paths
- Set up Docker Compose if you want both services running locally with one command
- Configure CI/CD pipelines for each repo independently
```

**If any command fails**, print the exact error output and stop. Do not continue to the next phase.

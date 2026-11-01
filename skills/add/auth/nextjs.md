<!-- ref: add/auth/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = Next.js. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js

Adds **better-auth** (typed, SSO + email/password) to a templateCentral Next.js project.

> **Security requirement**: verify `package.json` → `next` meets the floor in `.claude/rules/nextjs.md` before proceeding. Older versions carry `proxy.ts` auth-bypass advisories that silently defeat this skill.

### Files this skill creates

```
src/
├── lib/
│   ├── auth.ts                                        ← better-auth server config (verbatim — do not generate)
│   ├── auth-client.ts                                 ← better-auth client config (verbatim — do not generate)
│   └── authz.ts                                       ← hasRole / isOwner checks
├── proxy.ts                                           ← route protection middleware (verbatim — do not generate)
└── app/
    ├── api/
    │   └── auth/
    │       └── [...all]/
    │           └── route.ts
    ├── (public)/
    │   └── login/
    │       └── page.tsx
    └── dashboard/           ← only if not already created by scaffold
        ├── layout.tsx
        └── (overview)/
            └── page.tsx
test/lib/authz.test.ts
src/features/
└── auth/
    ├── components/
    │   ├── login-card.tsx
    │   ├── login-button.tsx
    │   ├── signout-button.tsx
    │   └── index.ts
    └── index.ts
```

### Files this skill modifies

```
.env.example                         ← adds BETTER_AUTH_SECRET, BETTER_AUTH_URL, NEXT_PUBLIC_APP_NAME, NEXT_PUBLIC_APP_URL
.env.local                           ← same vars (fill actual values)
src/lib/constants/routes.ts          ← adds PAGE_ROUTES.LOGIN (HOME and DASHBOARD already exist from scaffold)
AGENTS.md                            ← adds auth architecture notes
```

> **`providers.tsx` needs no change** — `authClient.useSession()` holds session state; no `SessionProvider`.

### Steps

#### Step 0 — Verify context

Need `<!-- templateCentral: nextjs@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

#### 1. Install better-auth

```bash
pnpm add "better-auth@^1.7.7"
```

Then run `TC_PART=leaf TC_LEAF=add/auth/nextjs bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/auth/nextjs/template/` into the project per `<skill-dir>/auth/nextjs/template.manifest` — the files of Steps 2, 3, 5, 7, 10 and 14 — and writes nothing, ending with a `STOP:` line, when a path is in the way.

> **Version floor:** see `.claude/rules/nextjs.md` (security advisories, and the schema regeneration the Drizzle adapter needs after upgrading).

#### 2. Write `src/lib/auth.ts` (verbatim — do not generate)

Security-critical file. Copied verbatim from `<skill-dir>/auth/nextjs/template/src/lib/auth.ts` by the copy step; do not re-type it.

> `freshAge` (under `session`, for high-assurance flows) counts from session `createdAt`, not last activity: with `43200`, users re-authenticate after 12 h regardless of activity.

> **Database**: with no `database` option, better-auth keeps accounts and sessions in process memory — lost on every restart, and broken across instances (serverless, replicas). `cookieCache` is only a 5-minute read-through cache, not storage. Add an adapter via `templatecentral:add` (database) before anything beyond local prototyping. With Drizzle v1, use `add/database/typescript/nextjs-drizzle.md` Step A9b (Relations v2 entry point); the default `better-auth/adapters/drizzle` output does not compile on Drizzle v1.

> **Password hashing**: the default is scrypt. For argon2id, install `@node-rs/argon2` and override `emailAndPassword.password.hash`/`.verify`:
> ```ts
> import { hash, verify, type Options } from '@node-rs/argon2';
>
> // Argon2id is the @node-rs/argon2 default algorithm; 64 MiB / t=3 / p=1.
> const opts: Options = { memoryCost: 65536, timeCost: 3, parallelism: 1, outputLen: 32 };
>
> emailAndPassword: {
>   // ...other options
>   password: {
>     hash: (password) => hash(password, opts),
>     verify: ({ hash: h, password }) => verify(h, password, opts),
>   },
> },
> ```

#### 3. Write `src/lib/auth-client.ts` (verbatim — do not generate)

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/lib/auth-client.ts` by the copy step; do not re-type it.

#### 4. Write `src/proxy.ts` (verbatim — do not generate)

Security-critical. Write exactly as shown; it replaces the scaffold's `src/proxy.ts`. Every response still passes through `applyFrameProtection`, so CSP and anti-clickjacking headers stay on (`/api/external/*` keeps the backend's headers).

```ts
import { getSessionCookie } from 'better-auth/cookies';
import { API_ROUTES, PAGE_ROUTES } from '@/lib/constants/routes';
import { applyFrameProtection } from '@/lib/security/frame-protection';
import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

const PUBLIC_PATHS = new Set<string>([PAGE_ROUTES.HOME, PAGE_ROUTES.LOGIN]);
const PUBLIC_API_PREFIXES = ['/api/auth', API_ROUTES.HEALTH];

function isApiRoute(pathname: string): boolean {
  return pathname.startsWith('/api/');
}

function isPublicRoute(pathname: string): boolean {
  return (
    PUBLIC_PATHS.has(pathname) ||
    PUBLIC_API_PREFIXES.some((p) => pathname.startsWith(p))
  );
}

export async function proxy(req: NextRequest) {
  return applyFrameProtection(req.nextUrl.pathname, await route(req));
}

async function route(req: NextRequest): Promise<Response> {
  const { pathname } = req.nextUrl;

  // Short-circuit for public routes that are not the login page
  if (isPublicRoute(pathname) && pathname !== PAGE_ROUTES.LOGIN) {
    return NextResponse.next();
  }

  // Optimistic check ONLY. getSessionCookie reads the cookie's presence with no
  // database call — this avoids a DB/session round-trip at the routing layer on every
  // request, keeping proxy latency low. It gates routing and redirects; it does NOT
  // validate the session (a forged cookie passes). The authoritative check MUST run
  // server-side in the protected layout (see step 8).
  const hasSession = getSessionCookie(req) != null;

  // Handle /login: redirect users who appear signed in to the dashboard, allow others through
  if (pathname === PAGE_ROUTES.LOGIN) {
    if (hasSession) {
      return NextResponse.redirect(new URL(PAGE_ROUTES.DASHBOARD, req.url));
    }
    return NextResponse.next();
  }

  // Protected routes: require a session cookie (authoritative validation happens in the layout)
  if (!hasSession) {
    if (isApiRoute(pathname)) {
      return new Response(null, { status: 401 });
    }
    return NextResponse.redirect(new URL(PAGE_ROUTES.LOGIN, req.url));
  }

  return NextResponse.next();
}

// Never configure a single-entry `i18n.locales` list — a high-severity security
// advisory covers exactly that shape: a single-locale list under Turbopack can skip
// the proxy entirely, so every auth check here silently stops running. If you add
// i18n routing, re-verify the proxy still executes on every matched path.
// See the Next.js floor in .claude/rules/nextjs.md.
export const config = {
  matcher: [
    '/((?!_next/static|_next/image|.*\\.(?:svg|png|jpg|jpeg|gif|ico|webp)$).*)',
  ],
};
```

#### 5. Create `src/app/api/auth/[...all]/route.ts`

Handlers are wrapped in `withLogging`; `pnpm check` rejects a bare `export const { GET, POST } = toNextJsHandler(auth)`.

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/app/api/auth/[...all]/route.ts` by the copy step; do not re-type it.

#### 6. Add `PAGE_ROUTES.LOGIN` to `src/lib/constants/routes.ts`

Add `LOGIN` to `PAGE_ROUTES` (`HOME` and `DASHBOARD` already exist — do not add them again):

```ts
export const PAGE_ROUTES = {
  // ... existing HOME: '/' and DASHBOARD: '/dashboard' entries
  LOGIN: '/login',
} as const;
```

#### 7. Create `src/app/(public)/login/page.tsx`

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/app/(public)/login/page.tsx` by the copy step; do not re-type it.

#### 8. Create `src/app/dashboard/layout.tsx` (skip if already exists)

> If the layout exists (scaffolded projects), **add the session check below to it** — do not rely on `proxy.ts`, which only checks that a cookie is present. `/dashboard` is protected only once this server-side check is in the layout; every protected route group needs one.

```tsx
import { auth } from '@/lib/auth';
import { Navbar } from '@/components/layout/navbar';
import { SiteFooter } from '@/components/layout/site-footer';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';

export default async function DashboardLayout({ children }: { children: ReactNode }) {
  // Authoritative gate. proxy.ts only checks cookie presence to keep routing fast; this
  // verifies the session's signature and, when the cookie cache is cold, revalidates it
  // against the store. Without this, a forged cookie would pass the proxy and reach
  // protected content. Note: with `cookieCache.enabled: true` (maxAge 5 min) this can be
  // served from the signed cookie without touching the store, so revocation and lockout
  // take effect only after that window — set `cookieCache.enabled: false` in
  // src/lib/auth.ts for high-assurance flows that need immediate revocation.
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session) {
    redirect(PAGE_ROUTES.LOGIN);
  }

  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </div>
  );
}
```

#### 9. Create `src/app/dashboard/(overview)/page.tsx` (skip if already exists)

> **Skip** if the page exists (scaffolded projects); the cleanup utility (`cat "<skill-dir>/../cleanup/SKILL.md"`) removes its `ExampleList` later.

If creating fresh (non-scaffold project):

```tsx
export default function DashboardPage() {
  return (
    <div className="container py-8">
      <h1 className="text-2xl font-bold">Dashboard</h1>
    </div>
  );
}
```

#### 10. Create `src/features/auth/` components

**`src/features/auth/components/login-button.tsx`** — SSO sign-in:

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/features/auth/components/login-button.tsx` by the copy step; do not re-type it.

**`src/features/auth/components/signout-button.tsx`**:

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/features/auth/components/signout-button.tsx` by the copy step; do not re-type it.

**`src/features/auth/components/login-card.tsx`**:

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/features/auth/components/login-card.tsx` by the copy step; do not re-type it.

**`src/features/auth/components/index.ts`**:

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/features/auth/components/index.ts` by the copy step; do not re-type it.

**`src/features/auth/index.ts`**:

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/features/auth/index.ts` by the copy step; do not re-type it.

#### 11. Update `.env.example` and `.env.local`

Add to both files:

```
# Auth — REQUIRED: generate secret with: openssl rand -base64 32
# WARNING: BETTER_AUTH_SECRET must be set in production — sessions are insecure without it
BETTER_AUTH_URL=http://localhost:3000
BETTER_AUTH_SECRET=

# App — used by auth.ts (appName) and auth-client.ts (baseURL)
NEXT_PUBLIC_APP_NAME=My App
NEXT_PUBLIC_APP_URL=http://localhost:3000

# Auth Providers (uncomment and fill for your provider)
# Google
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=

# GitHub
# GITHUB_CLIENT_ID=
# GITHUB_CLIENT_SECRET=

# Microsoft Entra ID
# MICROSOFT_CLIENT_ID=
# MICROSOFT_CLIENT_SECRET=

# Rate limiting (only if using the @upstash/ratelimit example — Redis.fromEnv() reads these)
# UPSTASH_REDIS_REST_URL=
# UPSTASH_REDIS_REST_TOKEN=
```

#### 12. Update project `AGENTS.md`

Add under `## Architecture Decisions`:

```markdown
- Auth via better-auth with `proxy.ts` route protection (`export async function proxy`); dev bypass with email/password when `isDev`
- `authClient` (src/lib/auth-client.ts) handles client-side session via `authClient.useSession()` — no SessionProvider needed
- Authorization via `src/lib/authz.ts` (`hasRole` / `isOwner`, deny by default); roles come from `user.role`, never client input
- Route groups: `(public)/` for public pages, `dashboard/` for authenticated pages
- Sessions: in-memory (non-persistent, single-instance) by default; add database adapter (via templatecentral:add (database)) before anything beyond local prototyping
```

#### 13. Session usage patterns

**Server Component or API route:**

```ts
import { auth } from '@/lib/auth';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { headers } from 'next/headers';
import { redirect } from 'next/navigation';

const session = await auth.api.getSession({ headers: await headers() });
if (!session) redirect(PAGE_ROUTES.LOGIN);

const { user } = session;
```

**Unauthenticated API response (never JSON — information-disclosure risk):**

```ts
if (!session) return new Response(null, { status: 401 });
```

**Client Component hook:**

```tsx
'use client';

import { authClient } from '@/lib/auth-client';

export function UserAvatar() {
  const { data: session, isPending } = authClient.useSession();

  if (isPending) return <Skeleton />;
  if (!session) return null;

  return <Avatar name={session.user.name} image={session.user.image} />;
}
```

#### 14. Authorization helpers

These decide what the caller may touch; both deny by default. `user.role` (Step 2) is stored server-side and never accepted from the client. With a database adapter, regenerate the auth schema to add the `role` column. With the cookie cache on, a revoked role reaches `hasRole` only after the cache max age.

**`src/lib/authz.ts`**:

Copied verbatim from `<skill-dir>/auth/nextjs/template/src/lib/authz.ts` by the copy step; do not re-type it.

Use `isOwner` on record-by-id pages, actions and handlers. Another user's record gets the same 404 as a missing one, so ids cannot be probed:

```tsx
// Server Component page
const item = await getItem(id);
if (!isOwner(item?.ownerId, session.user.id)) notFound();
```

```ts
// Route handler
if (!session) return new Response(null, { status: 401 });
if (!hasRole(session, 'admin')) return new Response(null, { status: 403 });

const item = await getItem(id);
if (!isOwner(item?.ownerId, session.user.id)) return new Response(null, { status: 404 });
```

**`test/lib/authz.test.ts`**:

Copied verbatim from `<skill-dir>/auth/nextjs/template/test/lib/authz.test.ts` by the copy step; do not re-type it.

#### 15. Adding an SSO provider

Add it to `socialProviders` in `src/lib/auth.ts`, credentials to `.env.local`, and a `<LoginButton provider="..." />` to `login-card.tsx`:

```ts
socialProviders: {
  google: {
    clientId: process.env.GOOGLE_CLIENT_ID!,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
  },
  microsoft: {
    clientId: process.env.MICROSOFT_CLIENT_ID!,
    clientSecret: process.env.MICROSOFT_CLIENT_SECRET!,
    // 'common' admits any Entra tenant; set your tenant ID for single-tenant apps.
    tenantId: 'common',
  },
},
```

| Provider | Config key | Required env vars | Callback URL |
|----------|------------|-------------------|--------------|
| Google | `google` | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | `/api/auth/callback/google` |
| GitHub | `github` | `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | `/api/auth/callback/github` |
| Microsoft | `microsoft` | `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET` | `/api/auth/callback/microsoft` |

All providers: https://www.better-auth.com/docs/authentication/social-sign-on

> **Acting as an OIDC provider** (issuing tokens to third parties): use `@better-auth/oauth-provider`; MCP is `@better-auth/mcp`; generic OAuth goes through `signIn.social` (PKCE on). The `oidcProvider` plugin was removed in better-auth 1.7. See https://www.better-auth.com/docs/plugins/oauth-provider.

### Rate Limiting (Required for Production)

Target: max 3 credential attempts per 15 minutes. better-auth's `rateLimit` runs in production only, stores in memory (per instance), and keys on a header clients can forge without a trusted proxy. For multiple instances, limit at the CDN/WAF/API Gateway or in `proxy.ts` with `@upstash/ratelimit` (Redis, edge-compatible):

```bash
pnpm add @upstash/ratelimit @upstash/redis
```

Put the check at the **top of `route()`** in `src/proxy.ts`, before the public-route short-circuit: `/api/auth/*` matches `PUBLIC_API_PREFIXES`, so a limiter placed after it never runs.

```typescript
import { Ratelimit } from '@upstash/ratelimit';
import { Redis } from '@upstash/redis';

// Max 3 attempts per 15 minutes, per client IP
const ratelimit = new Ratelimit({
  redis: Redis.fromEnv(),
  limiter: Ratelimit.slidingWindow(3, '15 m'),
  prefix: 'auth:credentials',
});

// Every credential-accepting auth endpoint, not just sign-in: sign-up, password
// reset and forgot-password are equally brute-forceable and all sit under the
// /api/auth public prefix.
const RATE_LIMITED_AUTH_PATHS = [
  '/api/auth/sign-in',
  '/api/auth/sign-up',
  '/api/auth/request-password-reset',
  '/api/auth/forget-password',
  '/api/auth/reset-password',
];

// TRUST_PROXY = number of trusted proxy hops (1 = ALB → App, 2 = ALB →
// Traefik → App); empty/unset = X-Forwarded-For is not trusted.
// Returns null when no trustworthy client IP can be derived.
function getRateLimitKey(req: NextRequest): string | null {
  const hops = Number(process.env.TRUST_PROXY);
  if (!hops) return null;
  const entries = (req.headers.get('x-forwarded-for') ?? '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
  // Take the right-most entry that is not a trusted hop: each trusted proxy
  // appends exactly one entry, so with one hop the client IP is the last
  // entry, with two hops the second-to-last. Anything further left is
  // client-forgeable.
  return entries[entries.length - hops] ?? null;
}

// At the top of route(), immediately after `const { pathname } = req.nextUrl;`
// and BEFORE the isPublicRoute() short-circuit (which would otherwise return
// NextResponse.next() for /api/auth/* and skip this check entirely):
if (RATE_LIMITED_AUTH_PATHS.some((p) => req.nextUrl.pathname.startsWith(p))) {
  // Fail closed when no trustworthy client IP exists (TRUST_PROXY unset or
  // header missing): all such requests share one bucket, keeping the endpoint
  // throttled instead of wide open. Fix the deployment topology — never fall
  // back to a client-supplied header.
  const key = getRateLimitKey(req) ?? 'untrusted';
  const { success } = await ratelimit.limit(key);
  if (!success) return new Response(null, { status: 429 });
}
```

> **TRUST_PROXY required**: trust `X-Forwarded-For` only behind a controlled reverse proxy (ALB, Traefik); otherwise clients forge it to bypass the limit. Set `TRUST_PROXY` to the trusted hop count (`1` for ALB → App, `2` for ALB → Traefik → App); leave it unset with no proxy. Same convention as `src/lib/utils/request-origin.ts`.

Single instance: the built-in limiter suffices — `rateLimit: { storage: 'database', customRules: { '/sign-in/*': { window: 900, max: 3 } } }` (paths are relative to `/api/auth`).

### Security Rules

- NEVER return JSON from `proxy.ts` for unauthorized API routes — use `new Response(null, { status: 401 })` (JSON leaks information).
- NEVER remove `disableSignUp: process.env.NODE_ENV === 'production'` unless open registration is intended.
- NEVER remove the `isDev` guard on the dev login button.
- NEVER hardcode secrets.
- NEVER expose `BETTER_AUTH_SECRET` in `NEXT_PUBLIC_*` vars — exposed to every browser.
- Every page, Server Action and handler that touches a record by id checks `isOwner` (or filters by owner) first; another user's record → same 404 as missing.
- NEVER accept `role` from client input — keep `input: false` on the `role` field and change roles only from trusted server code.
- Generate `BETTER_AUTH_SECRET` with `openssl rand -base64 32`.
- Rate limiting on auth endpoints is mandatory before production.
- Override the scrypt default with argon2id (Step 2) — the project standard.
- Reject breached passwords at sign-up/change (e.g. the Have I Been Pwned k-anonymity range API) before `authClient.signUp.email()`, in addition to the length floor.

### After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.

---

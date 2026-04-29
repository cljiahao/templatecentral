---
name: nextjs-add-auth
description: Use when the user wants to add authentication, configure an SSO provider (Microsoft Entra ID, Google, GitHub, etc.), protect routes, or add a login page to a Next.js project.
---

# Add Auth to Next.js

Add authentication to a Next.js project scaffolded from templateCentral. Uses **better-auth** — a TypeScript-first auth library with full type safety, SSO, and email/password support.

## Files this skill creates

```
src/
├── lib/
│   ├── auth.ts                                        ← better-auth server config (verbatim — do not generate)
│   └── auth-client.ts                                 ← better-auth client config (verbatim — do not generate)
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
src/features/
└── auth/
    ├── components/
    │   ├── login-card.tsx
    │   ├── login-button.tsx
    │   ├── signout-button.tsx
    │   └── index.ts
    └── index.ts
```

## Files this skill modifies

```
.env.example                         ← adds BETTER_AUTH_SECRET, BETTER_AUTH_URL, NEXT_PUBLIC_APP_URL
.env.local                           ← same vars (fill actual values)
src/lib/constants/routes.ts          ← adds PAGE_ROUTES.LOGIN (HOME and DASHBOARD already exist from scaffold)
AGENTS.md                            ← adds auth architecture notes
```

> **`providers.tsx` does NOT need modification** — better-auth manages session state via `authClient.useSession()`; no `SessionProvider` wrapper is required.

## Steps

### 1. Install better-auth

```bash
pnpm add better-auth@latest
```

> **Security**: Versions 1.6.5–1.6.6 contained critical security patches. Always install `better-auth@latest` (≥ 1.6.6) — never pin to an older version.

### 2. Write `src/lib/auth.ts` (verbatim — do not generate)

Security-critical file. Write exactly as shown.

```ts
import { betterAuth } from 'better-auth';
import { nextCookies } from 'better-auth/next-js';

export const auth = betterAuth({
  appName: process.env.NEXT_PUBLIC_APP_NAME ?? 'My App',
  baseURL: process.env.BETTER_AUTH_URL,
  secret: process.env.BETTER_AUTH_SECRET,

  emailAndPassword: {
    enabled: true,
    disableSignUp: process.env.NODE_ENV === 'production', // SSO only in prod; dev can sign up
    minPasswordLength: 8,
    autoSignIn: true,
  },

  socialProviders: {
    // --- Add your SSO providers here ---
    // Uncomment and supply env vars for each provider you want to enable.
    //
    // google: {
    //   clientId: process.env.GOOGLE_CLIENT_ID!,
    //   clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    // },
    // github: {
    //   clientId: process.env.GITHUB_CLIENT_ID!,
    //   clientSecret: process.env.GITHUB_CLIENT_SECRET!,
    // },
    // microsoft: {
    //   clientId: process.env.MICROSOFT_CLIENT_ID!,
    //   clientSecret: process.env.MICROSOFT_CLIENT_SECRET!,
    //   tenantId: 'common', // or a specific tenant ID for single-tenant apps
    // },
  },

  session: {
    expiresIn: 30 * 24 * 60 * 60, // 30 days
    updateAge: 24 * 60 * 60,       // refresh after 1 day of activity
    cookieCache: {
      enabled: true,
      maxAge: 5 * 60,              // 5-minute client-side cache
    },
  },

  advanced: {
    defaultCookieAttributes: {
      sameSite: 'lax',
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
    },
  },

  plugins: [nextCookies()], // must be last
});
```

> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. Adapters for Prisma, Drizzle, and Kysely are available — see [better-auth database docs](https://www.better-auth.com/docs/concepts/database).

### 3. Write `src/lib/auth-client.ts` (verbatim — do not generate)

```ts
import { createAuthClient } from 'better-auth/react';

export const authClient = createAuthClient({
  baseURL: process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000',
});
```

### 4. Write `src/proxy.ts` (verbatim — do not generate)

Security-critical file. Write exactly as shown.

```ts
import { auth } from '@/lib/auth';
import { API_ROUTES, PAGE_ROUTES } from '@/lib/constants/routes';
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
  const { pathname } = req.nextUrl;

  // Short-circuit for public routes that are not the login page
  if (isPublicRoute(pathname) && pathname !== PAGE_ROUTES.LOGIN) {
    return NextResponse.next();
  }

  const session = await auth.api.getSession({ headers: req.headers });

  // Handle /login: redirect authenticated users to dashboard, allow others through
  if (pathname === PAGE_ROUTES.LOGIN) {
    if (session) {
      return NextResponse.redirect(new URL(PAGE_ROUTES.DASHBOARD, req.url));
    }
    return NextResponse.next();
  }

  // Protected routes: require authentication
  if (!session) {
    if (isApiRoute(pathname)) {
      return new Response(null, { status: 401 });
    }
    return NextResponse.redirect(new URL(PAGE_ROUTES.LOGIN, req.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|.*\\.(?:svg|png|jpg|jpeg|gif|ico|webp)$).*)',
  ],
};
```

### 5. Create `src/app/api/auth/[...all]/route.ts`

```ts
import { auth } from '@/lib/auth';
import { toNextJsHandler } from 'better-auth/next-js';

export const { GET, POST } = toNextJsHandler(auth);
```

### 6. Add `PAGE_ROUTES.LOGIN` to `src/lib/constants/routes.ts`

Add `LOGIN` to the existing `PAGE_ROUTES` object. `HOME` and `DASHBOARD` are already present from the scaffold — do not add them again:

```ts
export const PAGE_ROUTES = {
  // ... existing HOME: '/' and DASHBOARD: '/dashboard' entries
  LOGIN: '/login',
} as const;
```

### 7. Create `src/app/(public)/login/page.tsx`

```tsx
import { LoginCard } from '@/features/auth';

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center">
      <LoginCard />
    </main>
  );
}
```

### 8. Create `src/app/dashboard/layout.tsx` (skip if already exists)

> **Skip this step** if `src/app/dashboard/layout.tsx` already exists — present when the project was scaffolded with templateCentral. The `proxy.ts` allowlist protects `/dashboard` automatically once this skill completes; no structural change is needed.

```tsx
import { Navbar } from '@/components/layout/navbar';
import { SiteFooter } from '@/components/layout/site-footer';
import type { ReactNode } from 'react';

export default function DashboardLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </div>
  );
}
```

### 9. Create `src/app/dashboard/(overview)/page.tsx` (skip if already exists)

> **Skip this step** if `src/app/dashboard/(overview)/page.tsx` already exists — present when the project was scaffolded with templateCentral. The existing page shows the `ExampleList` component; `shared-remove-example` cleans it up when the user is ready.

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

### 10. Create `src/features/auth/` components

**`src/features/auth/components/login-button.tsx`** — SSO sign-in:

```tsx
'use client';

import { authClient } from '@/lib/auth-client';
import type { ComponentProps } from 'react';

import { Button } from '@/components/ui/button';

interface LoginButtonProps extends ComponentProps<typeof Button> {
  provider: 'google' | 'github' | 'microsoft';
  callbackURL?: string;
  label?: string;
}

export function LoginButton({
  provider,
  callbackURL = '/dashboard',
  label = 'Sign in',
  ...buttonProps
}: LoginButtonProps) {
  return (
    <Button
      onClick={() => authClient.signIn.social({ provider, callbackURL })}
      {...buttonProps}
    >
      {label}
    </Button>
  );
}
```

**`src/features/auth/components/signout-button.tsx`:**

```tsx
'use client';

import { authClient } from '@/lib/auth-client';
import { useRouter } from 'next/navigation';
import type { ComponentProps } from 'react';

import { Button } from '@/components/ui/button';

interface SignOutButtonProps extends ComponentProps<typeof Button> {
  redirectTo?: string;
}

export function SignOutButton({
  redirectTo = '/',
  children = 'Sign out',
  ...buttonProps
}: SignOutButtonProps) {
  const router = useRouter();

  async function handleSignOut() {
    await authClient.signOut();
    router.push(redirectTo);
  }

  return (
    <Button onClick={handleSignOut} {...buttonProps}>
      {children}
    </Button>
  );
}
```

**`src/features/auth/components/login-card.tsx`:**

```tsx
'use client';

import { authClient } from '@/lib/auth-client';
import { isDev } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { useRouter } from 'next/navigation';

import { Button } from '@/components/ui/button';
import { CustomCard } from '@/components/widgets/custom-card';
import { LoginButton } from './login-button';

const DEV_EMAIL = 'dev@local';
const DEV_PASSWORD = 'dev-password-local';

export function LoginCard() {
  const router = useRouter();

  async function handleDevLogin() {
    const { error } = await authClient.signIn.email({
      email: DEV_EMAIL,
      password: DEV_PASSWORD,
    });

    if (error) {
      // First run: account does not exist yet — create it (autoSignIn: true signs in immediately)
      await authClient.signUp.email({
        email: DEV_EMAIL,
        password: DEV_PASSWORD,
        name: 'Dev User',
      });
    }

    router.push(PAGE_ROUTES.DASHBOARD);
  }

  return (
    <CustomCard header="Sign in" className="w-full max-w-sm">
      <div className="flex flex-col gap-3">
        {/* Add SSO provider buttons here — one LoginButton per provider */}
        {isDev && (
          <Button onClick={handleDevLogin} variant="outline">
            Dev login (bypass auth)
          </Button>
        )}
      </div>
    </CustomCard>
  );
}
```

**`src/features/auth/components/index.ts`:**

```ts
export { LoginButton } from './login-button';
export { LoginCard } from './login-card';
export { SignOutButton } from './signout-button';
```

**`src/features/auth/index.ts`:**

```ts
export * from './components';
```

### 11. Update `.env.example` and `.env.local`

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
```

### 12. Update project `AGENTS.md`

Add under `## Architecture Decisions`:

```markdown
- Auth via better-auth with `proxy.ts` route protection (`export async function proxy`); dev bypass with email/password when `isDev`
- `authClient` (src/lib/auth-client.ts) handles client-side session via `authClient.useSession()` — no SessionProvider needed
- Route groups: `(public)/` for public pages, `dashboard/` for authenticated pages
- Sessions: stateless JWE cookies by default; add database adapter (via nextjs-add-database) for session revocation
```

### 13. Session usage patterns

**Server Component or API route:**

```ts
import { auth } from '@/lib/auth';
import { headers } from 'next/headers';
import { redirect } from 'next/navigation';

const session = await auth.api.getSession({ headers: await headers() });
if (!session) redirect(PAGE_ROUTES.LOGIN);

const { user } = session;
// user.id, user.name, user.email, user.image
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

### 14. Adding an SSO provider

Uncomment the relevant block in `src/lib/auth.ts` and add credentials to `.env.local`. Then add a `<LoginButton provider="..." />` in `src/features/auth/components/login-card.tsx`.

| Provider | Config key | Required env vars | Callback URL |
|----------|------------|-------------------|--------------|
| Google | `google` | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | `/api/auth/callback/google` |
| GitHub | `github` | `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | `/api/auth/callback/github` |
| Microsoft | `microsoft` | `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET` | `/api/auth/callback/microsoft` |

Full provider list: https://www.better-auth.com/docs/authentication/social-sign-on

## Security Rules

- NEVER return JSON from `proxy.ts` for unauthorized API routes — use `new Response(null, { status: 401 })`. JSON responses create information-disclosure vectors.
- NEVER remove `disableSignUp: process.env.NODE_ENV === 'production'` — open registration in production is a security risk unless intentional.
- NEVER remove the `isDev` guard on the dev login button — it must only render in development.
- NEVER hardcode secrets — always environment variables.
- NEVER expose `BETTER_AUTH_SECRET` in `NEXT_PUBLIC_*` vars — exposed to every browser.
- Always generate `BETTER_AUTH_SECRET` with `openssl rand -base64 32` — never use a weak or predictable value.

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

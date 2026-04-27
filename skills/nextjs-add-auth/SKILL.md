---
name: nextjs-add-auth
description: Use when the user wants to add authentication, configure an SSO provider (Microsoft Entra ID, Google, GitHub, etc.), protect routes, or add a login page to a Next.js project.
---

# Add Auth to Next.js

Add authentication to a Next.js project scaffolded from templateCentral. This skill creates the full auth stack from scratch: NextAuth config, route protection middleware, login UI, and dashboard route group.

## Files this skill creates

```
src/
├── auth.ts                                        ← NextAuth config (verbatim — do not generate)
├── proxy.ts                                       ← route protection middleware (verbatim — do not generate)
└── app/
    ├── api/
    │   └── auth/
    │       └── [...nextauth]/
    │           └── route.ts
    ├── (public)/
    │   └── login/
    │       └── page.tsx
    └── dashboard/
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
.env.example                         ← adds AUTH_URL, AUTH_SECRET, provider var stubs
.env.local                           ← same vars (fill actual values)
src/lib/constants/routes.ts          ← adds PAGE_ROUTES.LOGIN, PAGE_ROUTES.DASHBOARD
src/components/layout/providers.tsx  ← adds SessionProvider wrapping QueryClientProvider
AGENTS.md                            ← adds auth architecture notes
```

## Steps

### 1. Install next-auth

```bash
pnpm add next-auth
```

### 2. Write `src/auth.ts` (verbatim — do not generate)

Security-critical file. Write exactly as shown — do not let the model generate this.

```ts
import { isDev } from '@/lib/constants/env';
import NextAuth, { type NextAuthConfig } from 'next-auth';
import Credentials from 'next-auth/providers/credentials';

const SESSION_MAX_AGE = 30 * 24 * 60 * 60;

const DEV_USER = {
  id: 'dev',
  name: 'Dev User',
  email: 'dev@local',
  image: null as string | null,
};

function getProviders(): NextAuthConfig['providers'] {
  const providers: NextAuthConfig['providers'] = [];

  // --- Add your SSO providers here ---
  // Example: Microsoft Entra ID
  // const hasEntraId =
  //   process.env.AUTH_MICROSOFT_ENTRA_ID_ID &&
  //   process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET &&
  //   process.env.AUTH_MICROSOFT_ENTRA_ID_ISSUER;
  //
  // if (hasEntraId) {
  //   providers.push(
  //     MicrosoftEntraID({
  //       clientId: process.env.AUTH_MICROSOFT_ENTRA_ID_ID!,
  //       clientSecret: process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET!,
  //       issuer: process.env.AUTH_MICROSOFT_ENTRA_ID_ISSUER!,
  //     })
  //   );
  // }

  if (isDev) {
    providers.push(
      Credentials({
        name: 'Dev',
        credentials: {
          email: { label: 'Email', type: 'text' },
          password: { label: 'Password', type: 'password' },
        },
        async authorize() {
          return DEV_USER;
        },
      })
    );
  }

  return providers;
}

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: getProviders(),
  callbacks: {
    async jwt({ token, user, profile }) {
      if (user) {
        token.id = user.id;
        token.name = user.name;
        token.email = user.email;
        token.image = user.image;
      }
      if (profile?.picture) {
        token.image = profile.picture;
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.id = token.id as string;
        session.user.name = token.name as string;
        session.user.email = token.email as string;
        session.user.image = token.image as string;
      }
      return session;
    },
    authorized: async ({ auth }) => !!auth,
  },
  trustHost: true,
  session: { strategy: 'jwt', maxAge: SESSION_MAX_AGE },
  jwt: { maxAge: SESSION_MAX_AGE },
});
```

### 3. Write `src/proxy.ts` (verbatim — do not generate)

Security-critical file. Write exactly as shown.

```ts
import { auth } from '@/auth';
import { API_ROUTES, PAGE_ROUTES } from '@/lib/constants/routes';
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

export const proxy = auth((req) => {
  const { pathname } = req.nextUrl;
  const isAuthenticated = !!req.auth;

  if (!isAuthenticated && !isPublicRoute(pathname)) {
    if (isApiRoute(pathname)) {
      return new Response(null, { status: 401 });
    }
    return NextResponse.redirect(new URL(PAGE_ROUTES.LOGIN, req.url));
  }

  if (isAuthenticated && pathname === PAGE_ROUTES.LOGIN) {
    return NextResponse.redirect(new URL(PAGE_ROUTES.DASHBOARD, req.url));
  }

  return NextResponse.next();
});

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|.*\\.(?:svg|png|jpg|jpeg|gif|ico|webp)$).*)',
  ],
};
```

### 4. Create `src/app/api/auth/[...nextauth]/route.ts`

```ts
import { handlers } from '@/auth';

export const { GET, POST } = handlers;
```

### 5. Add `PAGE_ROUTES.LOGIN` and `PAGE_ROUTES.DASHBOARD` to `src/lib/constants/routes.ts`

Open the file and add the two routes to the `PAGE_ROUTES` object:

```ts
export const PAGE_ROUTES = {
  HOME: '/',
  LOGIN: '/login',
  DASHBOARD: '/dashboard',
  // ... existing routes
} as const;
```

### 6. Create `src/app/(public)/login/page.tsx`

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

### 7. Create `src/app/dashboard/layout.tsx`

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

### 8. Create `src/app/dashboard/(overview)/page.tsx`

```tsx
export default function DashboardPage() {
  return (
    <div className="container py-8">
      <h1 className="text-2xl font-bold">Dashboard</h1>
    </div>
  );
}
```

### 9. Create `src/features/auth/` components

**`src/features/auth/components/login-button.tsx`:**

```tsx
'use client';

import { signIn } from 'next-auth/react';
import type { ComponentProps } from 'react';

import { Button } from '@/components/ui/button';

interface LoginButtonProps extends ComponentProps<typeof Button> {
  provider: string;
  redirectTo?: string;
  label?: string;
}

export function LoginButton({
  provider,
  redirectTo = '/dashboard',
  label = 'Sign in',
  ...buttonProps
}: LoginButtonProps) {
  return (
    <Button onClick={() => signIn(provider, { redirectTo })} {...buttonProps}>
      {label}
    </Button>
  );
}
```

**`src/features/auth/components/signout-button.tsx`:**

```tsx
'use client';

import { signOut } from 'next-auth/react';
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
  return (
    <Button onClick={() => signOut({ redirectTo })} {...buttonProps}>
      {children}
    </Button>
  );
}
```

**`src/features/auth/components/login-card.tsx`:**

```tsx
import { CustomCard } from '@/components/widgets/custom-card';
import { isDev } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { LoginButton } from './login-button';

export function LoginCard() {
  return (
    <CustomCard header="Sign in" className="w-full max-w-sm">
      <div className="flex flex-col gap-3">
        {/* Add SSO provider buttons here — one LoginButton per provider */}
        {isDev && (
          <LoginButton
            provider="credentials"
            redirectTo={PAGE_ROUTES.DASHBOARD}
            label="Dev login (bypass auth)"
            variant="outline"
          />
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

### 10. Update `src/components/layout/providers.tsx`

Add `SessionProvider` wrapping `QueryClientProvider`:

```tsx
'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SessionProvider } from 'next-auth/react';
import { useState, type ReactNode } from 'react';

interface ProvidersProps {
  children: ReactNode;
}

export function Providers({ children }: ProvidersProps) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,
            refetchOnWindowFocus: false,
          },
        },
      })
  );

  return (
    <SessionProvider>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </SessionProvider>
  );
}
```

### 11. Update `.env.example` and `.env.local`

Add to both files:

```
# Auth — REQUIRED: generate secret with: npx auth secret
# WARNING: AUTH_SECRET must be set in production — sessions are insecure without it
AUTH_URL=http://localhost:3000
AUTH_SECRET=

# Auth Providers (uncomment and fill for your provider)
# Microsoft Entra ID
# AUTH_MICROSOFT_ENTRA_ID_ID=
# AUTH_MICROSOFT_ENTRA_ID_SECRET=
# AUTH_MICROSOFT_ENTRA_ID_ISSUER=

# Google
# AUTH_GOOGLE_ID=
# AUTH_GOOGLE_SECRET=
```

### 12. Update project `AGENTS.md`

Add the following under `## Architecture Decisions`:

```markdown
- Auth via NextAuth (Auth.js) with `proxy.ts` route protection (`export const proxy = auth(...)`); dev bypass when `isDev`
- `SessionProvider` wraps `QueryClientProvider` in root `layout.tsx`
- Route groups: `(public)/` for public pages, `dashboard/` for authenticated pages
```

### 13. Adding an SSO provider (for the user to complete)

To add an SSO provider, open `src/auth.ts` and uncomment the relevant block in `getProviders()`. Each provider is guarded by env var checks — add the actual credentials to `.env.local`.

Common providers:

| Provider | Import | Required env vars |
|----------|--------|-------------------|
| Microsoft Entra ID | `next-auth/providers/microsoft-entra-id` | `AUTH_MICROSOFT_ENTRA_ID_ID`, `AUTH_MICROSOFT_ENTRA_ID_SECRET`, `AUTH_MICROSOFT_ENTRA_ID_ISSUER` |
| Google | `next-auth/providers/google` | `AUTH_GOOGLE_ID`, `AUTH_GOOGLE_SECRET` |
| GitHub | `next-auth/providers/github` | `AUTH_GITHUB_ID`, `AUTH_GITHUB_SECRET` |

Full list: https://authjs.dev/getting-started/providers

After adding a provider, add a `LoginButton` for it in `src/features/auth/components/login-card.tsx`.

## Security Rules

- NEVER return JSON from `proxy.ts` for unauthorized API routes — use `new Response(null, { status: 401 })`. JSON responses create information-disclosure vectors.
- NEVER remove the `isDev` guard on the Credentials provider — it must only exist in development.
- NEVER hardcode secrets — always environment variables.
- NEVER expose `AUTH_SECRET` in `NEXT_PUBLIC_*` vars — exposed to every browser.
- Always guard SSO provider registration with env var checks — missing vars silently skip, never crash.
- Always generate `AUTH_SECRET` with `npx auth secret` — never use a weak or predictable value.

## After Writing Code

Dispatch in order:
1. `build-agent` — validate compilation
2. `review-agent` — check code standards

---
name: add-auth
description: Use when the user wants to add authentication, configure an SSO provider (Microsoft Entra ID, Google, GitHub, etc.), or customize the login flow in a Next.js project.
---

# Add Auth to Next.js

Configure authentication in a Next.js project scaffolded from templateCentral. The template ships with NextAuth (Auth.js) pre-wired — this skill covers adding SSO providers, customizing the login UI, and protecting routes.

## What the Template Already Provides

The scaffolded project includes a working auth setup out of the box:

| File | Purpose |
|------|---------|
| `src/auth.ts` | NextAuth config — providers, JWT callbacks, session config |
| `src/proxy.ts` | Next.js 16 proxy (replaces middleware) — uses named `export const proxy` convention to redirect unauthenticated users to `/login` |
| `src/app/api/auth/[...nextauth]/route.ts` | NextAuth API route handler |
| `src/features/auth/` | Auth feature module — `LoginCard`, `LoginButton`, `SignOutButton` |
| `src/app/(public)/login/page.tsx` | Login page |
| `src/components/layout/providers.tsx` | `SessionProvider` + `QueryClientProvider` (rendered in root layout) |
| `.env.example` | Auth environment variable placeholders |

In **development mode** (`isDev`), a "Dev login (bypass auth)" button is available that auto-authenticates as a dev user — no provider configuration needed.

## Steps

### 1. Choose a Provider

NextAuth supports 80+ providers. Common ones:

| Provider | Package import | Required env vars |
|----------|---------------|-------------------|
| Microsoft Entra ID | `next-auth/providers/microsoft-entra-id` | `AUTH_MICROSOFT_ENTRA_ID_ID`, `AUTH_MICROSOFT_ENTRA_ID_SECRET`, `AUTH_MICROSOFT_ENTRA_ID_ISSUER` |
| Google | `next-auth/providers/google` | `AUTH_GOOGLE_ID`, `AUTH_GOOGLE_SECRET` |
| GitHub | `next-auth/providers/github` | `AUTH_GITHUB_ID`, `AUTH_GITHUB_SECRET` |

Full list: https://authjs.dev/getting-started/providers

### 2. Add the Provider to `src/auth.ts`

In the `getProviders()` function, add a conditional block for your provider. Follow the existing pattern — only push the provider when all required env vars are set:

```typescript
import MicrosoftEntraID from 'next-auth/providers/microsoft-entra-id';

// Inside getProviders():
const hasEntraId =
  process.env.AUTH_MICROSOFT_ENTRA_ID_ID &&
  process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET &&
  process.env.AUTH_MICROSOFT_ENTRA_ID_ISSUER;

if (hasEntraId) {
  providers.push(
    MicrosoftEntraID({
      clientId: process.env.AUTH_MICROSOFT_ENTRA_ID_ID!,
      clientSecret: process.env.AUTH_MICROSOFT_ENTRA_ID_SECRET!,
      issuer: process.env.AUTH_MICROSOFT_ENTRA_ID_ISSUER!,
    })
  );
}
```

Multiple providers can coexist — each guarded by its own env var check.

### 3. Add Environment Variables

Update `.env.example` with the new provider's variables (commented out as documentation, matching the template's convention):

```bash
# Microsoft Entra ID
# AUTH_MICROSOFT_ENTRA_ID_ID=
# AUTH_MICROSOFT_ENTRA_ID_SECRET=
# AUTH_MICROSOFT_ENTRA_ID_ISSUER=
```

Add the actual values to `.env.local` (note: `AUTH_URL` is already in `.env.example` and defaults to `http://localhost:3000`):

```bash
AUTH_SECRET=<generate with: npx auth secret>
AUTH_MICROSOFT_ENTRA_ID_ID=<your-client-id>
AUTH_MICROSOFT_ENTRA_ID_SECRET=<your-client-secret>
AUTH_MICROSOFT_ENTRA_ID_ISSUER=https://login.microsoftonline.com/<tenant-id>/v2.0
```

### 4. Add Login Button to `LoginCard`

In `src/features/auth/components/login-card.tsx`, add a `LoginButton` for the provider above the dev login button:

```typescript
<LoginButton
  provider="microsoft-entra-id"
  redirectTo={PAGE_ROUTES.DASHBOARD}
  label="SSO Login"
  className="py-6 text-lg"
/>
```

The `provider` string must match the NextAuth provider ID (lowercase, hyphenated).

### 5. Customize Public Routes (Optional)

In `src/proxy.ts` (the Next.js 16 proxy, exported as `export const proxy`), the `PUBLIC_PATHS` set controls which pages are accessible without auth. Add paths as needed:

```typescript
const PUBLIC_PATHS = new Set<string>([
  PAGE_ROUTES.HOME,
  PAGE_ROUTES.LOGIN,
  '/about',  // example: make /about public
]);
```

The `/api/auth/*` and `/api/health` routes are always public (required for NextAuth and Docker HEALTHCHECK respectively).

### 6. Access Session in Components

**Server components** — use the `auth()` function:

```typescript
import { auth } from '@/auth';

export default async function DashboardPage() {
  const session = await auth();
  const user = session?.user;
  // ...
}
```

**Client components** — use the `useSession()` hook:

```typescript
'use client';
import { useSession } from 'next-auth/react';

export function UserGreeting() {
  const { data: session } = useSession();
  const user = session?.user;
  // ...
}
```

### 7. Validate

1. Start the dev server (`pnpm dev`) — confirm no import errors
2. Visit `/login` — confirm the dev bypass button appears
3. Click "Dev login" — confirm redirect to `/dashboard`
4. Visit `/dashboard` directly while logged out — confirm redirect to `/login`
5. If an SSO provider is configured, test the full OAuth flow

## Dev Bypass Behavior

The Credentials provider and "Dev login" button are **only available when `isDev` is true** (`NODE_ENV === 'development'`). In production builds, they are completely excluded — no code path exists to bypass auth.

## Architecture

```
src/
├── auth.ts                              # NextAuth config (providers, callbacks)
├── proxy.ts                             # Next.js 16 proxy — `export const proxy = auth(...)` for route protection
├── app/api/auth/[...nextauth]/route.ts  # NextAuth API handler
├── features/auth/
│   ├── components/
│   │   ├── login-card.tsx               # Login UI with provider buttons
│   │   ├── login-button.tsx             # Reusable provider login button
│   │   ├── signout-button.tsx           # Sign-out button
│   │   └── index.ts                     # Component barrel
│   └── index.ts                         # Feature barrel
├── app/layout.tsx                       # Root layout — renders Providers here
└── components/layout/
    └── providers.tsx                     # SessionProvider + QueryClientProvider
```

## Rules

- NEVER hardcode secrets — always use environment variables
- NEVER remove the `isDev` guard on the Credentials provider — it must only exist in development
- NEVER return JSON from `proxy.ts` for unauthorized API routes — use `new Response(null, { status: 401 })` (Next.js 16 proxy constraint)
- Always guard provider registration with env var checks — missing vars should silently skip the provider, not crash
- Always generate `AUTH_SECRET` with `npx auth secret` — never use a weak or predictable value
- Keep the dev bypass pattern: `isDev` → Credentials provider + "Dev login" button

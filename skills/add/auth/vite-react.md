<!-- ref: add/auth/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = Vite + React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React

Configure authentication in a Vite + React SPA scaffolded from templateCentral. The template ships with a generic `AuthProvider` context — this skill covers integrating real auth backends, customizing the login UI, and protecting routes.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### What the Template Already Provides

The scaffolded project includes a working auth setup out of the box:

| File | Purpose |
|------|---------|
| `src/features/auth/components/auth-provider.tsx` | React context managing auth state (`user`, `login`, `logout`) |
| `src/features/auth/components/protected-route.tsx` | Route guard — redirects unauthenticated users to `/login` |
| `src/features/auth/components/login-card.tsx` | Login UI with dev bypass button |
| `src/features/auth/hooks/use-auth.ts` | `useAuth()` hook for consuming auth state |
| `src/features/auth/types.ts` | `AuthUser` and `AuthState` types |
| `src/pages/login.tsx` | Login page |
| `src/router.tsx` | Routes wrapped with `ProtectedRoute` for authenticated pages |
| `src/components/layout/providers.tsx` | `AuthProvider` wrapping the app |

In **development mode** (`ENV.IS_DEV`), the user is auto-authenticated as a dev user — no backend needed.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Choose an Auth Strategy

Since Vite + React is a client-side SPA, authentication is handled by a backend API. Common patterns:

| Strategy | How it works |
|----------|-------------|
| **Token-based (JWT)** | Backend returns a JWT on login; SPA stores it and sends via `Authorization` header |
| **Cookie-based (session)** | Backend sets an HttpOnly cookie; SPA relies on cookies for API calls |
| **OAuth redirect** | SPA redirects to provider (Google, Azure); backend handles callback and sets session |

The `AuthProvider` is provider-agnostic — it manages local state. You wire it to your backend's auth endpoints.

**Cookie sessions need CSRF protection.** The moment the browser attaches the session cookie automatically (which is exactly what `credentials: 'include'` buys you), any other origin can trigger an authenticated state-changing request. Cookies are still the right choice — they keep the token out of JS reach — but they must be paired with all three of:

- **`SameSite=Strict`** (`Lax` at minimum) on the session cookie, backend-set alongside `HttpOnly` and `Secure`.
- **A CSRF token** on every non-GET request — the backend issues it as a readable `XSRF-TOKEN` cookie, the SPA echoes it back in an `X-CSRF-Token` header, and the backend rejects any mismatch. The attacker's page can make the browser send the session cookie but cannot read the token to echo it. The templateCentral backends sign the token with an HMAC bound to the session (OWASP signed double-submit), so an injected or stale token fails too.
- **A strict CORS allowlist** on the backend — never `Access-Control-Allow-Origin: *` together with credentials.

**Same-origin only:** cookie mode requires the SPA to reach the API through a reverse proxy on its own origin (`VITE_API_BASE_URL=/api` → Vite `server.proxy` in dev, nginx `location /api/` in production — snippets in `templatecentral:standards (full-stack-pairing)`); the backend's `XSRF-TOKEN` cookie is host-only, so a direct call to an API on another host leaves `csrfHeader()` empty and every non-GET 403s.

**Backend contract.** The FastAPI and NestJS auth skills implement all three in their **Browser Client (Cookie Mode)** section — enable it on the backend (`templatecentral:add (auth)` there; `templatecentral:standards (full-stack-pairing)` says when). Their stock auth reads only `Authorization: Bearer`, so without cookie mode every guarded call from this SPA is a 401. The service below targets exactly these endpoints (under `VITE_API_BASE_URL`):

| Call | Endpoint | Notes |
|------|----------|-------|
| Login | `POST /auth/session` | JSON `{ email, password }` → 204 + `Set-Cookie` (HttpOnly session + `XSRF-TOKEN`); no token in the body |
| Current user | `GET /auth/me` | cookie-authenticated; FastAPI returns `{ id, email, name }`, NestJS `{ id, email }` |
| Logout | `POST /auth/logout` | 204, clears both cookies |
| Any other non-GET | — | must send `X-CSRF-Token` (`csrfHeader()`, sent for you by `ApiClient` — Step 3) or the backend answers 403 |

Token-based (JWT in an `Authorization` header) auth is not cookie-borne and therefore not CSRF-exposed — but it forfeits `HttpOnly`, so the token must live in memory only (see the `localStorage` rule below).

#### 2. Create the CSRF Helper and Auth Service

`csrfHeader()` is the single source for the CSRF header. It lives in `src/lib/clients/` (not the auth feature) because `ApiClient` (Step 3) needs it and `lib/` never imports from `features/`:

```typescript
// src/lib/clients/csrf.ts
/** Echoes the backend-issued XSRF-TOKEN cookie as X-CSRF-Token (signed double-submit); `{}` when absent. */
export function csrfHeader(): Record<string, string> {
  const token = document.cookie
    .split('; ')
    .find((c) => c.startsWith('XSRF-TOKEN='))
    ?.slice('XSRF-TOKEN='.length);
  return token ? { 'X-CSRF-Token': decodeURIComponent(token) } : {};
}
```

Create `src/features/auth/api/auth-service.ts` to handle backend communication:

```typescript
import { csrfHeader } from '@/lib/clients/csrf';
import { getApiBaseUrl } from '@/lib/constants/env';
import { APIError } from '@/lib/errors';
import { z } from 'zod';
import type { AuthUser } from '../types';

// Resolved per-request, never at module scope: getApiBaseUrl() throws when
// VITE_API_BASE_URL is unset, and a module-scope throw kills bundle evaluation
// before createRoot() runs — a blank page with no ErrorBoundary to catch it.
const authBase = () => `${getApiBaseUrl()}/auth`;

// Validate API response shapes at the boundary — mirrors the AuthUser type.
const authUserSchema = z
  .object({
    id: z.string(),
    // NestJS's /auth/me returns only the token claims (id, email) — fall back to email.
    name: z.string().optional(),
    email: z.email(),
    // AuthUser has it — without this, parse() silently strips it
    image: z.string().nullable().optional(),
  })
  .transform((u): AuthUser => ({ ...u, name: u.name ?? u.email }));

// POST /auth/session is the backend's browser login (cookie mode): it sets the HttpOnly
// session cookie plus XSRF-TOKEN and returns 204 — the JWT never reaches JavaScript.
export async function loginWithCredentials(email: string, password: string): Promise<AuthUser> {
  const res = await fetch(`${authBase()}/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
    credentials: 'include',
  });

  if (!res.ok) {
    throw new APIError({
      statusCode: res.status,
      data: await res.json().catch(() => ({ message: 'Login failed' })),
    });
  }

  const user = await fetchCurrentUser();
  if (!user) throw new APIError({ statusCode: 401 });
  return user;
}

export async function fetchCurrentUser(): Promise<AuthUser | null> {
  const res = await fetch(`${authBase()}/me`, { credentials: 'include' });
  if (!res.ok) return null;
  return authUserSchema.parse(await res.json());
}

export async function logoutUser(): Promise<void> {
  const res = await fetch(`${authBase()}/logout`, {
    method: 'POST',
    headers: csrfHeader(),
    credentials: 'include',
  });
  if (!res.ok) throw new APIError({ statusCode: res.status });
}
```

#### 3. Send the Session and CSRF Token from `ApiClient`

Every other backend call goes through `ApiClient` (`src/lib/clients/api-client.ts`, defined once in `templatecentral:standards (full-stack-pairing)` → Frontend HTTP Client — create it from there first if it is missing). Add these two members to that class — do not redefine it; every feature client that extends it inherits them:

```typescript
// src/lib/clients/api-client.ts — add to the existing ApiClient class
import { csrfHeader } from './csrf';
import { FetchClient, type HttpMethod } from './fetch-client';

  // Sends the session cookie on every call (same-origin via the /api proxy).
  protected override credentials: RequestCredentials = 'include';

  protected override requestHeaders(method: HttpMethod): Record<string, string> {
    return method === 'GET' ? {} : csrfHeader();
  }
```

The auth service above keeps raw `fetch` on purpose: login runs before any session exists, and `fetchCurrentUser` maps any non-2xx to "signed out" instead of throwing.

#### 4. Wire AuthProvider to the Backend

Update `src/features/auth/components/auth-provider.tsx` to check for an existing session on mount and call the backend for login/logout:

```tsx
import { ENV } from '@/lib/constants/env';
import { createContext, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { fetchCurrentUser, logoutUser } from '../api/auth-service';
import type { AuthUser } from '../types';

export const DEV_USER: AuthUser = {
  id: 'dev',
  name: 'Dev User',
  email: 'dev@local',
};

interface AuthContextValue {
  user: AuthUser | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (user: AuthUser) => void;
  logout: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);

interface AuthProviderProps {
  children: ReactNode;
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<AuthUser | null>(
    ENV.IS_DEV ? DEV_USER : null
  );
  const [isLoading, setIsLoading] = useState(!ENV.IS_DEV);

  useEffect(() => {
    if (ENV.IS_DEV) return;

    fetchCurrentUser()
      .then(setUser)
      // A network failure or a ZodError from authUserSchema.parse() would otherwise
      // reject unhandled and leave isLoading stuck; treat either as "not signed in".
      .catch(() => setUser(null))
      .finally(() => setIsLoading(false));
  }, []);

  const login = useCallback((authUser: AuthUser) => {
    setUser(authUser);
  }, []);

  const logout = useCallback(async () => {
    try {
      await logoutUser();
    } finally {
      setUser(null);
    }
  }, []);

  const value = useMemo(
    () => ({
      user,
      isAuthenticated: !!user,
      isLoading,
      login,
      logout,
    }),
    [user, isLoading, login, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
```

#### 5. Add a Login Form

Update `src/features/auth/components/login-card.tsx`. Use the project's canonical form pattern (React Hook Form + Zod + `CustomFormField`):

```tsx
import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { Form } from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { CustomCard, CustomFormField } from '@/components/widgets';
import { ENV } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { loginWithCredentials } from '../api/auth-service';
import { DEV_USER } from './auth-provider';
import { useAuth } from '../hooks/use-auth';

const loginSchema = z.object({
  email: z.email({ error: 'Invalid email address' }),
  password: z.string().min(1, 'Password is required'),
});

type LoginFormValues = z.input<typeof loginSchema>;

export function LoginCard() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [serverError, setServerError] = useState<string | null>(null);

  const form = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  });

  const onSubmit = async (values: LoginFormValues) => {
    setServerError(null);
    try {
      const user = await loginWithCredentials(values.email, values.password);
      login(user);
      navigate(PAGE_ROUTES.DASHBOARD);
    } catch {
      setServerError('Invalid credentials');
    }
  };

  const handleDevLogin = () => {
    login(DEV_USER);
    navigate(PAGE_ROUTES.DASHBOARD);
  };

  return (
    <CustomCard header="Sign in" headingLevel="h1" description="Enter your credentials to continue.">
      <Form {...form}>
        <form onSubmit={form.handleSubmit(onSubmit)} className="flex flex-col gap-4">
          <CustomFormField name="email" label="Email">
            <Input type="email" placeholder="you@example.com" />
          </CustomFormField>

          <CustomFormField name="password" label="Password">
            <Input type="password" placeholder="Password" />
          </CustomFormField>

          {serverError && (
            <p role="alert" className="text-sm text-destructive">
              {serverError}
            </p>
          )}

          <Button type="submit" disabled={form.formState.isSubmitting}>
            {form.formState.isSubmitting ? 'Signing in...' : 'Sign in'}
          </Button>
        </form>
      </Form>
      {ENV.IS_DEV && (
        <Button type="button" variant="outline" className="mt-4 w-full" onClick={handleDevLogin}>
          Dev login (bypass auth)
        </Button>
      )}
    </CustomCard>
  );
}
```

#### 6. Add Protected Routes

In `src/router.tsx`, wrap authenticated routes with `ProtectedRoute`. The template already has `<BrowserRouter>` wrapping the route tree — edit only inside the existing `<Routes>`:

```tsx
import { ProtectedRoute } from '@/features/auth';

{/* Inside the existing <Routes> in router.tsx */}
<Route element={<RootLayout />}>
  {/* Public routes */}
  <Route index element={<HomePage />} />
  <Route path="login" element={<LoginPage />} />

  {/* Protected routes */}
  <Route element={<ProtectedRoute />}>
    <Route path="dashboard" element={<DashboardPage />} />
    {/* Add more protected routes here */}
  </Route>

  <Route path="*" element={<NotFoundPage />} />
</Route>
```

Do NOT replace the entire `router.tsx` — only modify the route definitions inside the existing `<BrowserRouter>` and `<Routes>` wrappers.

#### 7. Add a Sign-Out Button

Use the `useAuth()` hook to access `logout`:

```tsx
import { Button } from '@/components/ui/button';
import { useAuth } from '@/features/auth';

export function SignOutButton() {
  const { logout } = useAuth();

  return (
    <Button type="button" variant="outline" onClick={logout}>
      Log out
    </Button>
  );
}
```

#### 8. Validate

1. Start the dev server (`pnpm dev`) — confirm no import errors
2. In dev mode, the `AuthProvider` auto-authenticates (dev bypass) — confirm `/dashboard` loads without redirect
3. On `/login`, confirm the dev login card renders and "Dev login" button works
4. To test the real redirect flow, temporarily disable the dev bypass in `auth-provider.tsx` — visiting `/dashboard` while unauthenticated should redirect to `/login`
5. If a backend is configured (with cookie mode enabled), test the full login/logout flow — DevTools should show the session cookie as `HttpOnly` and every POST carrying `X-CSRF-Token`
6. Run tests (`pnpm test`) — confirm no regressions

### Dev Bypass Behavior

When `ENV.IS_DEV` is `true` (`import.meta.env.DEV`), the `AuthProvider` initializes with a pre-authenticated dev user and skips the backend session check. The "Dev login" button is also only rendered in dev mode. In production builds, Vite tree-shakes these code paths entirely.

### Architecture

```
src/
├── features/auth/
│   ├── api/
│   │   └── auth-service.ts          # Backend auth API calls
│   ├── components/
│   │   ├── auth-provider.tsx         # React context (user state, login/logout)
│   │   ├── protected-route.tsx       # Route guard (redirects to /login)
│   │   ├── login-card.tsx            # Login UI
│   │   └── index.ts                  # Component barrel
│   ├── hooks/
│   │   ├── use-auth.ts              # useAuth() hook
│   │   └── index.ts                  # Hook barrel
│   ├── types.ts                      # AuthUser, AuthState
│   └── index.ts                      # Feature barrel
├── pages/login.tsx                    # Login page
├── router.tsx                         # ProtectedRoute wrapping auth'd routes
├── lib/clients/
│   ├── csrf.ts                        # csrfHeader() — single source of X-CSRF-Token
│   └── api-client.ts                  # ApiClient: credentials + CSRF on non-GET
└── components/layout/
    └── providers.tsx                  # AuthProvider wrapping the app
```

### Rules

- NEVER store tokens in `localStorage` — use HttpOnly cookies (set by the backend) or in-memory state
- NEVER remove the `ENV.IS_DEV` guard on the dev bypass — it must only exist in development
- NEVER put auth logic directly in page components — use the `useAuth()` hook
- Call the backend through `ApiClient` subclasses (Step 3), never a raw `fetch` — it is the one place that sends `credentials: 'include'` and, on every non-GET, `X-CSRF-Token`. The auth service's own three calls are the only exception
- Always redirect to `/login` on 401 responses — the `ProtectedRoute` handles this for navigation, but API calls should also handle 401s gracefully
- Keep the dev bypass pattern: `ENV.IS_DEV` → auto-authenticated dev user + "Dev login" button

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards

<!-- ref: add/auth/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = Vite + React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React

Wires the template's generic `AuthProvider` to a real backend, adds the login UI and protects routes in a templateCentral Vite + React SPA.

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

Need `<!-- templateCentral: vite-react@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

#### 1. Choose an Auth Strategy

Auth lives in a backend API. Common patterns:

| Strategy | How it works |
|----------|-------------|
| **Token-based (JWT)** | Backend returns a JWT on login; SPA stores it and sends via `Authorization` header |
| **Cookie-based (session)** | Backend sets an HttpOnly cookie; SPA relies on cookies for API calls |
| **OAuth redirect** | SPA redirects to provider (Google, Azure); backend handles callback and sets session |

`AuthProvider` is provider-agnostic local state; wire it to the backend's endpoints.

**Cookie sessions need CSRF protection.** Once the browser attaches the session cookie automatically (`credentials: 'include'`), any origin can trigger an authenticated state change. Cookies still win — they keep the token out of JS — but need all three of:

- **`SameSite=Strict`** (`Lax` at minimum) on the session cookie, backend-set alongside `HttpOnly` and `Secure`.
- **A CSRF token** on every non-GET request — the backend issues it as a readable `XSRF-TOKEN` cookie, the SPA echoes it back in an `X-CSRF-Token` header, and the backend rejects any mismatch. An attacker's page can send the cookie but cannot read the token. The templateCentral backends HMAC-bind the token to the session (OWASP signed double-submit), so injected or stale tokens fail too.
- **A strict CORS allowlist** on the backend — never `Access-Control-Allow-Origin: *` together with credentials.

**Same-origin only:** cookie mode requires the SPA to reach the API through a reverse proxy on its own origin (`VITE_API_BASE_URL=/api` → Vite `server.proxy` in dev, nginx `location /api/` in production — snippets in `templatecentral:standards (full-stack-pairing)`); the backend's `XSRF-TOKEN` cookie is host-only, so a direct call to an API on another host leaves `csrfHeader()` empty and every non-GET 403s.

**Backend contract.** The FastAPI and NestJS auth skills implement all three in their **Browser Client (Cookie Mode)** section — enable it on the backend (`templatecentral:add (auth)` there; `templatecentral:standards (full-stack-pairing)` says when). Without it their auth reads only `Authorization: Bearer`, so every guarded call from this SPA is a 401. The service below targets these endpoints (under `VITE_API_BASE_URL`):

| Call | Endpoint | Notes |
|------|----------|-------|
| Login | `POST /auth/session` | JSON `{ email, password }` → 204 + `Set-Cookie` (HttpOnly session + `XSRF-TOKEN`); no token in the body (`/auth/login` still returns the JWT for API clients) |
| Current user | `GET /auth/me` | cookie-authenticated; FastAPI returns `{ id, email, name }`, NestJS `{ id, email }` |
| Logout | `POST /auth/logout` | 204, clears both cookies |
| Any other non-GET | — | must send `X-CSRF-Token` (`csrfHeader()`, sent for you by `ApiClient` — Step 3) or the backend answers 403 |

Bearer-token auth is not CSRF-exposed but forfeits `HttpOnly`, so the token lives in memory only (see the `localStorage` rule).

#### 2. Create the CSRF Helper and Auth Service

Run `TC_PART=leaf TC_LEAF=add/auth/vite-react bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"`. It copies both files below from `<skill-dir>/auth/vite-react/template/` per `<skill-dir>/auth/vite-react/template.manifest`, and writes nothing, ending with a `STOP:` line, when a path is in the way.

`csrfHeader()` is the single source for the CSRF header. It lives in `src/lib/clients/` (not the auth feature) because `ApiClient` (Step 3) needs it and `lib/` never imports from `features/`:

`src/lib/clients/csrf.ts` is copied verbatim from `<skill-dir>/auth/vite-react/template/src/lib/clients/csrf.ts` by the copy step; do not re-type it.

`src/features/auth/api/auth-service.ts` handles backend communication:

Copied verbatim from `<skill-dir>/auth/vite-react/template/src/features/auth/api/auth-service.ts` by the copy step; do not re-type it.

#### 3. Send the Session and CSRF Token from `ApiClient`

Every other backend call goes through `ApiClient` (`src/lib/clients/api-client.ts`; create it from `templatecentral:standards (full-stack-pairing)` → Frontend HTTP Client if missing). Add these two members — do not redefine the class; subclasses inherit them:

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

In `src/router.tsx`, wrap authenticated routes with `ProtectedRoute` — edit only inside the existing `<Routes>`; do NOT replace the file:

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

When `ENV.IS_DEV` (`import.meta.env.DEV`) is true, `AuthProvider` starts with a dev user and skips the session check, and the "Dev login" button renders. Production builds tree-shake both.

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
- Redirect to `/login` on 401 — `ProtectedRoute` covers navigation; API calls must handle 401 too
- Keep the dev bypass pattern: `ENV.IS_DEV` → auto-authenticated dev user + "Dev login" button
- Role and ownership checks in the SPA only hide UI. The API must enforce them on every request

### After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.

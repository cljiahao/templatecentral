---
name: shared-add-auth
description: Use when the user wants to add authentication, protect routes, or implement login/logout in any templateCentral project — FastAPI, NestJS, Next.js, or Vite + React.
---

# Add Auth

## Stack Detection

Before starting, identify the project stack:

| Signal file | Stack |
|---|---|
| `requirements.txt` containing `fastapi` | FastAPI |
| `nest-cli.json` | NestJS |
| `next.config.ts` / `next.config.js` / `next.config.mjs` | Next.js |
| `vite.config.ts` / `vite.config.js` (no `next.config.*`) | Vite + React |

Then jump directly to the matching stack section below.

---

## FastAPI

Add JWT-based authentication to a FastAPI project scaffolded from templateCentral.

> **Stub notice:** The auth service created here is intentionally incomplete — `register_user` stores nothing and `login_user` raises HTTP 501 until a database is available. Run `fastapi-add-database` after this skill to complete the integration.

## Prerequisites

Requires a project scaffolded with `templatecentral:fastapi-scaffold`. See Step 0.

## Dependencies

Add to `requirements.txt`:
- `PyJWT[crypto]` — JWT encoding/decoding
- `argon2-cffi` — Password hashing (argon2id algorithm; OWASP/NIST SP 800-63B recommended)
- `email-validator` — Pydantic `EmailStr` validation (validates email format in request schemas)

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Add Auth Schemas

Create request/response schemas for auth endpoints.

**`src/api/schemas/request/auth.py`**:
```python
from pydantic import EmailStr, Field

from api.schemas.base import BaseRequestSchema


class RegisterRequest(BaseRequestSchema):
    """Registration request."""

    email: EmailStr = Field(description="User email address.")
    password: str = Field(min_length=12, description="User password — minimum 12 characters (NIST SP 800-63B).")
    name: str = Field(description="User display name.")


class LoginRequest(BaseRequestSchema):
    """Login request."""

    email: EmailStr = Field(description="User email address.")
    password: str = Field(description="User password.")
```

**`src/api/schemas/response/auth.py`**:
```python
from pydantic import BaseModel, Field

from api.schemas.base import BaseResponseSchema


class TokenResponse(BaseModel):
    """JWT token response — uses plain BaseModel to preserve OAuth2-standard snake_case (RFC 6749)."""

    access_token: str = Field(description="JWT access token.")
    token_type: str = Field(default="bearer", description="Token type.")


class UserResponse(BaseResponseSchema):
    """Authenticated user info."""

    id: str = Field(description="User ID.")
    email: str = Field(description="User email.")
    name: str = Field(description="User display name.")
```

### 2. Extend Config

Add `SECRET_KEY` and `ACCESS_TOKEN_EXPIRE_MINUTES` to `APISettings` in **`src/core/config.py`**:

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    SECRET_KEY: str = Field(description="JWT signing key — generate with: openssl rand -hex 32")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=30)
```

Add to `src/.env` (real value — never commit):
```
SECRET_KEY=
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

Document in `src/.env.default`:
```
SECRET_KEY=<generate with: openssl rand -hex 32>
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

> Run `openssl rand -hex 32` and paste the output as `SECRET_KEY`.

> **Security**: `SECRET_KEY` has no default — Pydantic will raise a validation error at startup if unset, which is the correct behavior. NEVER use a hardcoded default like `"change-me"` for secrets.

### 3. Create Security Module

**`src/core/security.py`** — JWT token creation/verification and password hashing:

```python
from datetime import datetime, timedelta, timezone

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
import jwt

from core.config import api_settings

ALGORITHM = "HS256"

_ph = PasswordHasher()  # argon2id, OWASP-recommended defaults


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return _ph.verify(hashed_password, plain_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def create_access_token(subject: str, expires_delta: timedelta | None = None) -> str:
    """Create a JWT access token."""
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=api_settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode = {"sub": subject, "exp": expire}
    return jwt.encode(to_encode, api_settings.SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> str | None:
    """Decode and validate a JWT token. Returns the subject or None."""
    try:
        # algorithms is a security whitelist — never omit or use ["none"]; omitting allows algorithm confusion attacks
        payload = jwt.decode(token, api_settings.SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError:
        return None
```

### 4. Create Auth Dependency

Create **`src/api/dependencies/`** directory (does not exist in base template), then add both **`src/api/dependencies/__init__.py`** (empty, marks the directory as a Python package) and **`src/api/dependencies/auth.py`** — `get_current_user` dependency for protecting routes:

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from core.security import decode_access_token

bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
    """Extract and validate the current user from the JWT token."""
    user_id = decode_access_token(credentials.credentials)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        )
    return user_id
```

### 5. Create Auth Service

**`src/api/services/auth_service.py`** — orchestrates registration and login. This is a stub; complete it after running `fastapi-add-database`.

```python
from fastapi import HTTPException, status

from core.security import create_access_token, hash_password, verify_password


def register_user(email: str, password: str, name: str) -> dict:
    """Register a new user. Persist to database after running fastapi-add-database."""
    hashed = hash_password(password)
    user_id = "generated-id"
    return {"id": user_id, "email": email, "name": name, "hashed_password": hashed}


def login_user(email: str, password: str) -> str:
    """Authenticate user and return JWT. Implement DB lookup after running fastapi-add-database."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Database integration required. Run fastapi-add-database to complete auth.",
    )
```

### 6. Add Auth Tag

Add `AUTH` to the `APITags` enum in **`src/api/tags.py`**:

```python
class APITags(StrEnum):
    # ... existing tags
    AUTH = "auth"
```

### 7. Create Auth Router

**`src/api/routers/auth.py`**:

```python
from fastapi import APIRouter, Depends

from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import login_user, register_user
from api.tags import APITags

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=UserResponse)
def register(body: RegisterRequest) -> UserResponse:
    """Register a new user account."""
    user = register_user(email=body.email, password=body.password, name=body.name)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = login_user(email=body.email, password=body.password)
    return TokenResponse(access_token=token)
```

### 8. Register the Router

Add the auth router to `src/api/routes.py`:

```python
from api.routers import auth
from api.tags import APITags

router.include_router(auth.router, tags=[APITags.AUTH])
```

### 9. Protect Routes

Use the `get_current_user` dependency on any endpoint that requires auth:

```python
from api.dependencies.auth import get_current_user

@router.get("/me", response_model=UserResponse)
def get_me(user_id: str = Depends(get_current_user)) -> UserResponse:
    """Get the current authenticated user. Implement DB lookup after running fastapi-add-database."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Database integration required. Run fastapi-add-database to complete auth.",
    )
```

## Rate Limiting (Required for Production)

Industry best practice: max 3 failed auth attempts per 15 minutes. Add `slowapi` to `requirements.txt`, then:

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request

limiter = Limiter(key_func=get_remote_address)
# In app.py:
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# On auth endpoints:
@router.post("/login")
@limiter.limit("3/15minutes")
async def login(request: Request, body: LoginRequest) -> TokenResponse: ...
```

## Rules

- **SECRET_KEY must be kept secret** — never commit to version control. Add to `src/.env` and `.gitignore`.
- Use `HTTPBearer` scheme so Swagger UI gets the "Authorize" button.
- Always hash passwords with argon2id (`argon2-cffi` package) — never store plaintext. Memory-hard and resistant to GPU-based brute-force (OWASP and NIST SP 800-63B recommendation).
- `get_current_user` returns the user ID (subject). Extend it to return a full user object once you have a database.
- **Rate limiting is mandatory for production** — add `slowapi` before going live.
- **TRUST_PROXY must be set when behind a reverse proxy** — `get_remote_address` reads `request.client.host`. Without `TRUST_PROXY`, the proxy's IP is the apparent client, making rate limiting shared across all users (ineffective).

## Validate

```bash
pytest test/ -v     # auth tests pass
ruff check src/     # zero lint errors
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate the server starts and tests pass
2. `shared-review-agent` — check code standards

---

## NestJS

Add JWT-based authentication to a NestJS project scaffolded from templateCentral using Passport.js.

> **Stub notice:** The `AuthService` created here is intentionally incomplete — `register` stores nothing and `login` throws `UnauthorizedException` until a database is available. Run `nestjs-add-database` after this skill to complete the integration.

## Prerequisites

Requires a project scaffolded with `templatecentral:nestjs-scaffold`. See Step 0.

## Dependencies

`argon2` is a native Node addon — pnpm blocks native builds by default. Before installing, add the following to `pnpm-workspace.yaml` in the project root (create the file if it doesn't exist):

```yaml
allowBuilds:
  argon2: true
```

Then install:

```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt argon2
pnpm add -D @types/passport-jwt
```

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Create Auth Module Directory

Create `src/modules/auth/` with these files (flat — no subdirectories, matching the template's module structure):
- `auth.module.ts`
- `auth.controller.ts`
- `auth.service.ts`
- `auth.dto.ts`
- `jwt.strategy.ts`
- `jwt-auth.guard.ts`

### 2. Define DTOs

**`src/modules/auth/auth.dto.ts`**:

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const registerSchema = z.object({
  email: z.email(),
  password: z.string().min(12), // 12-char minimum — NIST SP 800-63B baseline
  name: z.string().min(1),
});

const loginSchema = z.object({
  email: z.email(),
  password: z.string(),
});

const tokenSchema = z.object({
  accessToken: z.string(),
  tokenType: z.literal('bearer'),
});

export class RegisterDto extends createZodDto(registerSchema) {}
export class LoginDto extends createZodDto(loginSchema) {}
export class TokenDto extends createZodDto(tokenSchema) {}
```

### 3. Add Config

Add `JWT_SECRET` to `appConfig` in **`src/config/env.config.ts`**:

```typescript
export const appConfig = {
  // ... existing fields ...
  JWT_SECRET: process.env.JWT_SECRET!,
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || '30m',
};
```

Add to `.env` (generate real value — never commit):
```
JWT_SECRET=
JWT_EXPIRES_IN=30m
```

> Run `openssl rand -hex 32` and paste the output as `JWT_SECRET`.

**Add a startup guard in `src/main.ts`** — the `!` assertion is erased at compile time and does NOT throw at runtime if the variable is missing:

```typescript
async function bootstrap() {
  if (!appConfig.JWT_SECRET) {
    throw new Error('JWT_SECRET environment variable is required');
  }
  // ... rest of bootstrap
}
```

NEVER use a fallback like `?? ''` or `|| 'change-me'` for secrets.

### 4. Create JWT Strategy

**`src/modules/auth/jwt.strategy.ts`**:

```typescript
import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

import { appConfig } from '../../config/env.config';

interface JwtPayload {
  sub: string;
  email: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: appConfig.JWT_SECRET,
      algorithms: ['HS256'],
    });
  }

  validate(payload: JwtPayload) {
    return { id: payload.sub, email: payload.email };
  }
}
```

### 5. Create Auth Guard

**`src/modules/auth/jwt-auth.guard.ts`**:

```typescript
import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
```

### 6. Create Auth Service

**`src/modules/auth/auth.service.ts`**:

```typescript
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';

import type { RegisterDto, LoginDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(private readonly jwtService: JwtService) {}

  async register(dto: RegisterDto) {
    const hashedPassword = await argon2.hash(dto.password);  // argon2id by default
    const user = { id: 'generated-id', email: dto.email, name: dto.name, hashedPassword };
    return { id: user.id, email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    throw new UnauthorizedException('Database integration required. Run nestjs-add-database to complete auth.');
  }
}
```

### 7. Create Auth Controller

**`src/modules/auth/auth.controller.ts`**:

```typescript
import { Body, Controller, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';

import { AuthService } from './auth.service';
import { LoginDto, RegisterDto } from './auth.dto';

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  @ApiOperation({ summary: 'Register a new user' })
  register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Post('login')
  @ApiOperation({ summary: 'Authenticate and receive a JWT token' })
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }
}
```

### 8. Create Auth Module

**`src/modules/auth/auth.module.ts`**:

```typescript
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';

import { appConfig } from '../../config/env.config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [
    PassportModule,
    JwtModule.register({
      secret: appConfig.JWT_SECRET,
      signOptions: { expiresIn: appConfig.JWT_EXPIRES_IN },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

### 9. Export from Modules Barrel

Add the auth module to `src/modules/index.ts`:

```typescript
export * from './auth/auth.module';
```

### 10. Register in AppModule

Import `AuthModule` in `src/app.module.ts`:

```typescript
import { AuthModule } from './modules';

@Module({
  imports: [
    // ...existing modules
    AuthModule,
  ],
})
export class AppModule {}
```

### 11. Protect Routes

Use the `JwtAuthGuard` on any controller or endpoint that requires authentication:

```typescript
import { UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@UseGuards(JwtAuthGuard)
@Controller('tasks')
export class TaskController {
  // All endpoints in this controller require auth
}
```

Or on a single endpoint:

```typescript
@UseGuards(JwtAuthGuard)
@Get('me')
getMe(@Req() req) {
  return req.user; // { id, email } from JwtStrategy.validate()
}
```

## Environment Variables

Add to `.env` (real value — never commit):
```
JWT_SECRET=
JWT_EXPIRES_IN=30m
```

Document in `.env.example`:
```
JWT_SECRET=<generate with: openssl rand -hex 32>
JWT_EXPIRES_IN=30m
```

## Rate Limiting (Required for Production)

Industry best practice: max 3 failed auth attempts per 15 minutes. Install `@nestjs/throttler`:

```bash
pnpm add @nestjs/throttler
```

Register globally in `AppModule` (import + guard):

```typescript
import { ThrottlerModule, ThrottlerGuard, minutes } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';

@Module({
  imports: [
    ThrottlerModule.forRoot([{ ttl: minutes(15), limit: 3 }]),
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
```

## Rules

- **JWT_SECRET must be kept secret** — never commit to version control; document only as a placeholder in `.env.example`.
- Always hash passwords with argon2id — never store plaintext. Use the `argon2` npm package. Memory-hard and resistant to GPU-based brute-force (OWASP and NIST SP 800-63B recommendation).
- The `JwtStrategy.validate()` return value becomes `req.user` — extend it to return a full user object once you have a database.
- **Rate limiting is mandatory for production** — add `@nestjs/throttler` before going live.
- **TRUST_PROXY must be set when behind a reverse proxy** — `ThrottlerGuard` uses `req.ip`, which Fastify only patches from `X-Forwarded-For` when `trustProxy` is active (set via `TRUST_PROXY` in the scaffold). Without it, all proxied requests share the proxy's IP and hit the same rate bucket.

## Validate

```bash
pnpm build    # zero compile errors
pnpm test     # auth tests pass
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

---

## Next.js

Add authentication to a Next.js project scaffolded from templateCentral. Uses **better-auth** — a TypeScript-first auth library with full type safety, SSO, and email/password support.

## Prerequisites

Requires a project scaffolded with `templatecentral:nextjs-scaffold`. See Step 0.

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

### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Install better-auth

```bash
pnpm add better-auth
```

### 2. Write `src/lib/auth.ts` (verbatim — do not generate)

Security-critical file. Write exactly as shown.

```ts
import { betterAuth } from 'better-auth';
import { nextCookies } from 'better-auth/next-js';

if (!process.env.BETTER_AUTH_SECRET) {
  throw new Error('BETTER_AUTH_SECRET environment variable is required — generate with: openssl rand -base64 32');
}

export const auth = betterAuth({
  appName: process.env.NEXT_PUBLIC_APP_NAME ?? 'My App',
  baseURL: process.env.BETTER_AUTH_URL,
  secret: process.env.BETTER_AUTH_SECRET,

  emailAndPassword: {
    enabled: true,
    disableSignUp: process.env.NODE_ENV === 'production', // SSO only in prod; dev can sign up
    minPasswordLength: 12, // NIST SP 800-63B minimum
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
    expiresIn: 30 * 24 * 60 * 60, // 30 days (AAL1) — AAL2 systems reduce to 43200 (12h) + 30-min inactivity; AAL3 use 28800 (8h) + 15-min inactivity
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

> `freshAge` is measured from session `createdAt`, not last activity. If you set a short `freshAge` (e.g. 43200 for AAL2 flows), users must re-authenticate after that period regardless of activity — this is the intended behavior for high-security flows.

> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. The Drizzle adapter is a separate package (`@better-auth/drizzle` — install alongside `drizzle-orm`). See [better-auth database docs](https://www.better-auth.com/docs/concepts/database).

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

> **OIDC provider (token issuer)**: If your project needs to act as an OIDC provider (issuing tokens to third-party clients), use `@better-auth/oauth-provider` — the `oidc-provider` plugin has been removed. See: https://www.better-auth.com/docs/plugins/oauth-provider

## Rate Limiting (Required for Production)

Industry best practice: max 3 failed auth attempts per 15 minutes. better-auth does not include built-in rate limiting — add it at the infrastructure layer (CDN/WAF/API Gateway) or in `proxy.ts` middleware using `@upstash/ratelimit` (Redis-backed, edge-compatible):

```bash
pnpm add @upstash/ratelimit @upstash/redis
```

In `src/proxy.ts`, add a rate-limit check before the auth call on `/api/auth/sign-in`:

```typescript
// Rate limit sign-in attempts (max 3/15 min)
if (request.nextUrl.pathname === '/api/auth/sign-in/email') {
  const { success } = await ratelimit.limit(request.ip ?? 'anonymous');
  if (!success) return new Response(null, { status: 429 });
}
```

> **TRUST_PROXY required**: `request.ip` returns the reverse-proxy IP, not the real client IP, unless `TRUST_PROXY=true` is set. Without it, all sign-in attempts share the same bucket and one client can exhaust the limit for everyone. Set `TRUST_PROXY=true` for one-hop (ALB → App) or `TRUST_PROXY=2` for two-hop (ALB → Traefik → App) topologies. See the scaffold's `src/lib/utils/get-app-origin.ts` for the same pattern.

For simpler setups without Redis, use `next-rate-limit` with in-memory state (not suitable for multi-instance deployments).

## Security Rules

- NEVER return JSON from `proxy.ts` for unauthorized API routes — use `new Response(null, { status: 401 })`. JSON responses create information-disclosure vectors.
- NEVER remove `disableSignUp: process.env.NODE_ENV === 'production'` — open registration in production is a security risk unless intentional.
- NEVER remove the `isDev` guard on the dev login button — it must only render in development.
- NEVER hardcode secrets — always environment variables.
- NEVER expose `BETTER_AUTH_SECRET` in `NEXT_PUBLIC_*` vars — exposed to every browser.
- Always generate `BETTER_AUTH_SECRET` with `openssl rand -base64 32` — never use a weak or predictable value.
- **Rate limiting is mandatory for production** — add rate limiting on auth endpoints before going live.
- **Password hashing**: better-auth handles password hashing internally. For any custom hashing outside better-auth, use argon2id (`argon2` package) — OWASP and NIST SP 800-63B recommended.

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

---

## Vite + React

Configure authentication in a Vite + React SPA scaffolded from templateCentral. The template ships with a generic `AuthProvider` context — this skill covers integrating real auth backends, customizing the login UI, and protecting routes.

## Prerequisites

Requires a project scaffolded with `templatecentral:vite-react-scaffold`. See Step 0.

## What the Template Already Provides

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

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Choose an Auth Strategy

Since Vite + React is a client-side SPA, authentication is handled by a backend API. Common patterns:

| Strategy | How it works |
|----------|-------------|
| **Token-based (JWT)** | Backend returns a JWT on login; SPA stores it and sends via `Authorization` header |
| **Cookie-based (session)** | Backend sets an HttpOnly cookie; SPA relies on cookies for API calls |
| **OAuth redirect** | SPA redirects to provider (Google, Azure); backend handles callback and sets session |

The `AuthProvider` is provider-agnostic — it manages local state. You wire it to your backend's auth endpoints.

### 2. Create an Auth Service

Create `src/features/auth/api/auth-service.ts` to handle backend communication:

```typescript
import { getApiBaseUrl } from '@/lib/constants/env';
import { APIError } from '@/lib/errors';
import type { AuthUser } from '../types';

const API_BASE = getApiBaseUrl();
const AUTH_BASE = `${API_BASE}/auth`;

export async function loginWithCredentials(
  email: string,
  password: string
): Promise<AuthUser> {
  const res = await fetch(`${AUTH_BASE}/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
    credentials: 'include',
  });

  if (!res.ok) {
    throw new APIError({ statusCode: res.status, data: await res.json().catch(() => ({ message: 'Login failed' })) });
  }

  return res.json();
}

export async function fetchCurrentUser(): Promise<AuthUser | null> {
  const res = await fetch(`${AUTH_BASE}/me`, { credentials: 'include' });
  if (!res.ok) return null;
  return res.json();
}

export async function logoutUser(): Promise<void> {
  await fetch(`${AUTH_BASE}/logout`, {
    method: 'POST',
    credentials: 'include',
  });
}
```

### 3. Wire AuthProvider to the Backend

Update `src/features/auth/components/auth-provider.tsx` to check for an existing session on mount and call the backend for login/logout:

```typescript
import { ENV } from '@/lib/constants/env';
import { createContext, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { fetchCurrentUser, logoutUser } from '../api/auth-service';
import type { AuthUser } from '../types';

const DEV_USER: AuthUser = {
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
      .finally(() => setIsLoading(false));
  }, []);

  const login = useCallback((authUser: AuthUser) => {
    setUser(authUser);
  }, []);

  const logout = useCallback(async () => {
    await logoutUser();
    setUser(null);
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

### 4. Add a Login Form

Update `src/features/auth/components/login-card.tsx`. Use the project's canonical form pattern (React Hook Form + Zod + `CustomFormField`):

```typescript
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
    login({ id: 'dev', name: 'Dev User', email: 'dev@local' });
    navigate(PAGE_ROUTES.DASHBOARD);
  };

  return (
    <CustomCard header="Sign In" description="Enter your credentials to continue.">
      <Form {...form}>
        <form onSubmit={form.handleSubmit(onSubmit)} className="flex flex-col gap-4">
          <CustomFormField name="email" label="Email">
            <Input type="email" placeholder="you@example.com" />
          </CustomFormField>

          <CustomFormField name="password" label="Password">
            <Input type="password" placeholder="Password" />
          </CustomFormField>

          {serverError && <p className="text-sm text-red-500">{serverError}</p>}

          <Button type="submit" disabled={form.formState.isSubmitting}>
            {form.formState.isSubmitting ? 'Signing in...' : 'Sign in'}
          </Button>
        </form>
      </Form>
      {ENV.IS_DEV && (
        <button type="button"
          className="mt-4 w-full rounded-md border-2 bg-white px-4 py-3 text-sm text-gray-500 hover:bg-gray-100"
          onClick={handleDevLogin}>
          Dev login (bypass auth)
        </button>
      )}
    </CustomCard>
  );
}
```

### 5. Add Protected Routes

In `src/router.tsx`, wrap authenticated routes with `ProtectedRoute`. The template already has `<BrowserRouter>` wrapping the route tree — edit only inside the existing `<Routes>`:

```typescript
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

### 6. Add a Sign-Out Button

Use the `useAuth()` hook to access `logout`:

```typescript
import { useAuth } from '@/features/auth';

export function SignOutButton() {
  const { logout } = useAuth();

  return (
    <button type="button" onClick={logout}>
      Log out
    </button>
  );
}
```

### 7. Validate

1. Start the dev server (`pnpm dev`) — confirm no import errors
2. In dev mode, the `AuthProvider` auto-authenticates (dev bypass) — confirm `/dashboard` loads without redirect
3. On `/login`, confirm the dev login card renders and "Dev login" button works
4. To test the real redirect flow, temporarily disable the dev bypass in `auth-provider.tsx` — visiting `/dashboard` while unauthenticated should redirect to `/login`
5. If a backend is configured, test the full login/logout flow
6. Run tests (`pnpm test`) — confirm no regressions

## Dev Bypass Behavior

When `ENV.IS_DEV` is `true` (`import.meta.env.DEV`), the `AuthProvider` initializes with a pre-authenticated dev user and skips the backend session check. The "Dev login" button is also only rendered in dev mode. In production builds, Vite tree-shakes these code paths entirely.

## Architecture

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
└── components/layout/
    └── providers.tsx                  # AuthProvider wrapping the app
```

## Rules

- NEVER store tokens in `localStorage` — use HttpOnly cookies (set by the backend) or in-memory state
- NEVER remove the `ENV.IS_DEV` guard on the dev bypass — it must only exist in development
- NEVER put auth logic directly in page components — use the `useAuth()` hook
- Always use `credentials: 'include'` in fetch calls to send cookies to the backend
- Always redirect to `/login` on 401 responses — the `ProtectedRoute` handles this for navigation, but API calls should also handle 401s gracefully
- Keep the dev bypass pattern: `ENV.IS_DEV` → auto-authenticated dev user + "Dev login" button

## Validate

```bash
pnpm build    # zero errors
pnpm test     # auth tests pass
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

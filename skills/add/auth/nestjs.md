<!-- ref: add/auth/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS

Add JWT-based authentication to a NestJS project scaffolded from templateCentral using Passport.js.

> **Stub notice:** The `AuthService` created here is intentionally incomplete — both `register` and `login` throw `NotImplementedException` (501) until a database is available. Run `templatecentral:add` (database) after this skill to complete the integration.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### Dependencies

`argon2` is a native Node addon — pnpm blocks native builds by default. Before installing, uncomment the `# argon2: true` line already present under `allowBuilds:` in `pnpm-workspace.yaml` (do not add a second top-level `allowBuilds:` key — YAML silently drops earlier duplicate keys, which would remove the existing `lefthook`/`@scarf/scarf` entries):

```yaml
allowBuilds:
  '@scarf/scarf': false
  lefthook: false
  argon2: true
```

Then install:

```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt argon2
pnpm add -D @types/passport-jwt
```

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Create Auth Module Directory

Create `src/modules/auth/` with these files (flat — no subdirectories, matching the template's module structure):
- `auth.module.ts`
- `auth.controller.ts`
- `auth.service.ts`
- `auth.dto.ts`
- `jwt.strategy.ts`
- `jwt-auth.guard.ts`
- `roles.decorator.ts`
- `roles.guard.ts`
- `ownership.ts`

#### 2. Define DTOs

**`src/modules/auth/auth.dto.ts`**:

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const registerSchema = z.object({
  email: z.email(),
  // 128-char cap bounds argon2 hashing cost on this unauthenticated endpoint.
  password: z.string().min(12).max(128),
  name: z.string().min(1),
});

const loginSchema = z.object({
  email: z.email(),
  password: z.string().min(1).max(128),
});

const tokenSchema = z.object({
  accessToken: z.string(),
  tokenType: z.literal('bearer'),
});

export class RegisterDto extends createZodDto(registerSchema) {}
export class LoginDto extends createZodDto(loginSchema) {}
export class TokenDto extends createZodDto(tokenSchema) {}
```

#### 3. Add Config

Add `JWT_SECRET` and `JWT_EXPIRES_IN_SECONDS` to `envSchema` in **`src/config/env.config.ts`** — validated at import time, so a missing/short secret fails boot loudly instead of surfacing as a runtime `undefined`:

```typescript
const envSchema = z.object({
  // ... existing fields ...
  JWT_SECRET: z.string().min(32),
  JWT_EXPIRES_IN_SECONDS: z.coerce.number().int().positive().default(1800),
});
```

```typescript
export const appConfig = {
  // ... existing fields ...
  JWT_SECRET: env.JWT_SECRET,
  JWT_EXPIRES_IN_SECONDS: env.JWT_EXPIRES_IN_SECONDS,
};
```

Add to `.env` (generate real value — never commit):
```
JWT_SECRET=
JWT_EXPIRES_IN_SECONDS=1800
```

> Run `openssl rand -hex 32` and paste the output as `JWT_SECRET`.

Document in `.env.example`:
```
JWT_SECRET=<generate with: openssl rand -hex 32>
JWT_EXPIRES_IN_SECONDS=1800
```

NEVER use a fallback like `?? ''` or `|| 'change-me'` for secrets.

#### 4. Create JWT Strategy

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

export interface AuthUser {
  id: string;
  email: string;
  roles: string[];
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

  validate(payload: JwtPayload): AuthUser {
    // Roles are never taken from the token; load them from the database so a revoked role
    // stops working on the next request. Until then nobody holds a role.
    return { id: payload.sub, email: payload.email, roles: [] };
  }
}
```

#### 5. Create Auth Guard

**`src/modules/auth/jwt-auth.guard.ts`**:

```typescript
import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
```

#### 6. Create Authorization Helpers

Deny-by-default role and ownership checks. `JwtAuthGuard` says who the caller is; these decide what the caller may touch.

**`src/modules/auth/roles.decorator.ts`**:

```typescript
import { Reflector } from '@nestjs/core';

/** Roles allowed to call a handler; holding any one is enough. Handler metadata overrides class metadata. */
export const Roles = Reflector.createDecorator<string[]>();
```

**`src/modules/auth/roles.guard.ts`**:

```typescript
import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { FastifyRequest } from 'fastify';

import type { AuthUser } from './jwt.strategy';
import { Roles } from './roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride(Roles, [
      context.getHandler(),
      context.getClass(),
    ]);
    // A route behind this guard without @Roles is a mistake, so it is denied rather than opened.
    if (!required?.length) {
      throw new ForbiddenException('Insufficient permissions.');
    }
    // Partial: a customised validate() may omit roles, which must deny (403), not throw (500).
    const { user } = context
      .switchToHttp()
      .getRequest<FastifyRequest & { user?: Partial<AuthUser> }>();
    const roles = user?.roles;
    // A malformed roles list (any non-string entry) denies outright instead of being matched loosely.
    if (
      !Array.isArray(roles) ||
      !roles.every((role) => typeof role === 'string') ||
      !roles.some((role) => required.includes(role))
    ) {
      throw new ForbiddenException('Insufficient permissions.');
    }
    return true;
  }
}
```

**`src/modules/auth/ownership.ts`**:

```typescript
import { NotFoundException } from '@nestjs/common';

/** Throws unless `userId` owns the record; pass `undefined` when the record does not exist. */
export function assertOwner(ownerId: string | undefined, userId: string): void {
  // 404 rather than 403, so a caller cannot probe which ids belong to other users.
  if (ownerId === undefined || ownerId !== userId) {
    throw new NotFoundException('Not found.');
  }
}
```

List `RolesGuard` after `JwtAuthGuard` so `req.user` is set before roles are checked. Call `assertOwner` after loading a record by id, before returning or changing it:

```typescript
@Delete(':id')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(['admin'])
@ApiBearerAuth()
remove(@Param('id') id: string) {
  return this.taskService.remove(id);
}
```

```typescript
async update(id: string, userId: string, dto: UpdateTaskDto): Promise<void> {
  const task = await this.taskRepository.findById(id);
  assertOwner(task?.ownerId, userId);
  await this.taskRepository.update(id, dto);
}
```

#### 7. Create Auth Service

**`src/modules/auth/auth.service.ts`**:

```typescript
import { Injectable, Logger, NotImplementedException } from '@nestjs/common';

import type { LoginDto, RegisterDto, TokenDto } from './auth.dto';

// A missing database is an unimplemented feature (501), not a rejected credential (401):
// returning 401 would tell clients the credentials were wrong when nothing was checked.
// The remediation ("run templatecentral:add (database)") is operator-facing — it goes to
// the server log, never into the HTTP response body.
const STUB_REMEDIATION =
  'AuthService is a stub. Run templatecentral:add (database) to generate the real implementation.';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  register(_dto: RegisterDto) {
    this.logger.error(STUB_REMEDIATION);
    throw new NotImplementedException('Not implemented.');
  }

  // Typed so cookie mode's `await this.authService.login(dto)` compiles before the database
  // guide replaces this stub with the real (async) implementation.
  login(_dto: LoginDto): Promise<TokenDto> {
    this.logger.error(STUB_REMEDIATION);
    throw new NotImplementedException('Not implemented.');
  }
}
```

#### 8. Create Auth Controller

**`src/modules/auth/auth.controller.ts`**:

```typescript
import { Body, Controller, Get, HttpCode, HttpStatus, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { FastifyRequest } from 'fastify';

import { LoginDto, RegisterDto, TokenDto } from './auth.dto';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import type { AuthUser } from './jwt.strategy';

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
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Authenticate and receive a JWT token' })
  @ApiOkResponse({ type: TokenDto })
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Return the authenticated user' })
  me(@Req() req: FastifyRequest & { user: AuthUser }): AuthUser {
    return req.user;
  }
}
```

#### 9. Create Auth Module

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
      // Seconds, not an "30m" string: @nestjs/jwt types expiresIn as number | ms.StringValue,
      // which a plain Zod-validated string does not satisfy.
      signOptions: { algorithm: 'HS256', expiresIn: appConfig.JWT_EXPIRES_IN_SECONDS },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

#### 10. Export from Modules Barrel

Add the auth module to `src/modules/index.ts`:

```typescript
export * from './auth/auth.module';
```

#### 11. Register in AppModule

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

#### 12. Protect Routes

Use the `JwtAuthGuard` on any controller or endpoint that requires authentication:

```typescript
import { Controller, UseGuards } from '@nestjs/common';
import { ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
@Controller('tasks')
export class TaskController {
  // All endpoints in this controller require auth
}
```

For a single endpoint, put `@UseGuards(JwtAuthGuard)` + `@ApiBearerAuth()` on the handler — `AuthController.me` above is the pattern (`req.user` is what `JwtStrategy.validate()` returned).

#### 13. Test Env + Auth Tests

Vitest does not load `.env`, and `env.config.ts` now throws at import without `JWT_SECRET` — so every suite importing `AppModule` fails until the test configs supply one. In **both** `vitest.config.ts` and `vitest.config.e2e.ts`, add under `test:`:

```typescript
    // Vitest does not load .env, and env.config.ts rejects missing required values at import.
    env: { JWT_SECRET: 'test'.repeat(8) },
```

**`test/auth.e2e-spec.ts`**:

```typescript
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { JwtService } from '@nestjs/jwt';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Test } from '@nestjs/testing';
import { AppModule } from '../src/app.module';

describe('Auth (e2e)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication<NestFastifyApplication>(new FastifyAdapter());
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('rejects /auth/me without a token', async () => {
    const res = await app.inject({ method: 'GET', url: '/auth/me' });
    expect(res.statusCode).toBe(401);
  });

  it('returns the token subject on /auth/me', async () => {
    const token = await app.get(JwtService).signAsync({ sub: 'user-1', email: 'a@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: '/auth/me',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: 'user-1', email: 'a@example.com', roles: [] });
  });

  it('rejects a malformed login body', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/login', payload: { email: 'x' } });
    expect(res.statusCode).toBe(400);
  });
});
```

**`test/modules/auth/authz.spec.ts`** — unit tests for the role guard and ownership check; no app boot needed:

```typescript
import { describe, expect, it } from 'vitest';
import { ForbiddenException, NotFoundException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { assertOwner } from '../../../src/modules/auth/ownership';
import { Roles } from '../../../src/modules/auth/roles.decorator';
import { RolesGuard } from '../../../src/modules/auth/roles.guard';

// `this: void` lets each handler be passed around unbound, as Nest's ExecutionContext does.
class OpenController {
  list(this: void) {
    return [];
  }
}

class AdminController {
  @Roles(['admin'])
  remove(this: void) {
    return true;
  }
}

@Roles(['admin'])
class MixedController {
  @Roles(['user'])
  read(this: void) {
    return true;
  }
}

/** The two things RolesGuard reads: route metadata, and whatever user is on the request. */
function contextWithUser(
  controller: abstract new () => object,
  handler: () => unknown,
  user: object | undefined
): ExecutionContext {
  return {
    getHandler: () => handler,
    getClass: () => controller,
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as unknown as ExecutionContext;
}

/** A request carrying the user JwtStrategy.validate() returns. */
function contextFor(
  controller: abstract new () => object,
  handler: () => unknown,
  roles: string[]
): ExecutionContext {
  return contextWithUser(controller, handler, { id: 'u1', email: 'a@example.com', roles });
}

const guard = new RolesGuard(new Reflector());

describe('RolesGuard', () => {
  it('denies when the handler has no @Roles metadata', () => {
    const context = contextFor(OpenController, OpenController.prototype.list, ['admin']);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('denies a user without any required role', () => {
    const context = contextFor(AdminController, AdminController.prototype.remove, ['user']);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('allows a user holding one required role', () => {
    const context = contextFor(AdminController, AdminController.prototype.remove, ['admin']);
    expect(guard.canActivate(context)).toBe(true);
  });

  it('lets handler @Roles override class @Roles', () => {
    const context = contextFor(MixedController, MixedController.prototype.read, ['user']);
    expect(guard.canActivate(context)).toBe(true);
  });

  it('denies a request with no user', () => {
    const context = contextWithUser(AdminController, AdminController.prototype.remove, undefined);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('denies a roles list containing a non-string entry', () => {
    const user = { id: 'u1', email: 'a@example.com', roles: ['admin', 42] };
    const context = contextWithUser(AdminController, AdminController.prototype.remove, user);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('denies a user without a roles list', () => {
    const user = { id: 'u1', email: 'a@example.com' };
    const context = contextWithUser(AdminController, AdminController.prototype.remove, user);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });
});

describe('assertOwner', () => {
  it('assertOwner throws NotFoundException for another owner', () => {
    expect(() => assertOwner('u2', 'u1')).toThrow(NotFoundException);
  });

  it('assertOwner throws NotFoundException for a missing record', () => {
    expect(() => assertOwner(undefined, 'u1')).toThrow(NotFoundException);
  });

  it('assertOwner allows the owner', () => {
    expect(() => assertOwner('u1', 'u1')).not.toThrow();
  });
});
```

### Browser Client (Cookie Mode)

**Apply when a browser SPA calls this API** — a Vite + React frontend (`templatecentral:add (auth)` on Vite sends `credentials: 'include'` + `X-CSRF-Token`, never a Bearer header), or Next.js client components calling the backend. `templatecentral:standards (full-stack-pairing)` points here. Without it every `JwtAuthGuard` route answers that SPA with 401.

**Same-origin only:** the SPA must reach this API through a reverse proxy on its own origin (Vite `server.proxy` in dev, nginx `location /api/` in production, or a Next.js `rewrites()` path — snippets in `templatecentral:standards (full-stack-pairing)`); `XSRF-TOKEN` is a host-only cookie, so an SPA on another host cannot read it and every non-GET would 403.

Design (OWASP CSRF + Session Management cheat sheets, RFC 10017 *OAuth 2.0 for Browser-Based Applications* §6.1 cookie rules): the JWT rides in an `HttpOnly; Secure; SameSite=Strict; Path=/` cookie named `__Host-session` (`session` in dev, where `Secure` is off for plain-http localhost) — never in JS-readable storage. Unsafe methods carry a **signed double-submit** CSRF token: the readable `XSRF-TOKEN` cookie holds `nonce.HMAC(key, session, nonce)`, the SPA echoes it in `X-CSRF-Token`, and the guard recomputes the HMAC against the session cookie — so a token injected from a sibling subdomain or lifted from another session fails. Bearer requests skip the check (browsers never attach `Authorization` on their own), so API clients keep working unchanged. Hand-rolled on `node:crypto` rather than `@fastify/csrf-protection`, whose `onRequest`-hook model does not compose with Nest guards.

**1. Install** `@fastify/cookie` (11.x, fastify 5):

```bash
pnpm add @fastify/cookie
```

**2. `src/config/setups/security.setup.ts`** — register the plugin at the top of `setupSecurity()` (before Helmet). `setupCors()` stays as is: the SPA reaches this API same-origin through its proxy, so its requests never preflight:

```typescript
import fastifyCookie from '@fastify/cookie';

  // Parses req.cookies and adds reply.setCookie — required by the auth session cookie.
  await fastify.register(fastifyCookie);
```

**3. `src/modules/auth/auth.cookies.ts`**:

```typescript
import { ForbiddenException } from '@nestjs/common';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

import { appConfig } from '../../config/env.config';

// Secure is dropped only in dev (plain-http localhost); the __Host- prefix requires Secure,
// so the session cookie takes its hardened name everywhere else.
export const COOKIE_SECURE = appConfig.ENVIRONMENT !== 'dev';
export const SESSION_COOKIE = COOKIE_SECURE ? '__Host-session' : 'session';
// Readable by the SPA, which echoes it back in the X-CSRF-Token header (Fastify lower-cases
// incoming header names, hence the lookup key).
export const CSRF_COOKIE = 'XSRF-TOKEN';
export const CSRF_HEADER = 'x-csrf-token';
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);
// Sub-key so the CSRF HMAC never shares raw key material with JWT signing.
const CSRF_KEY = createHmac('sha256', appConfig.JWT_SECRET).update('csrf-v1').digest();

function csrfSignature(session: string, nonce: string): string {
  // Length-prefixed message (OWASP signed double-submit) binds the token to the session.
  return createHmac('sha256', CSRF_KEY)
    .update(`${session.length}!${session}!${nonce.length}!${nonce}`)
    .digest('hex');
}

function createCsrfToken(session: string): string {
  const nonce = randomBytes(32).toString('base64url');
  return `${nonce}.${csrfSignature(session, nonce)}`;
}

function verifyCsrfToken(token: string, session: string): boolean {
  const [nonce, signature = ''] = token.split('.', 2);
  if (!nonce) return false;
  const expected = Buffer.from(csrfSignature(session, nonce));
  const actual = Buffer.from(signature);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

// req.cookies exists only once @fastify/cookie is registered (setupSecurity) — suites that build
// the app without it must still get a clean 401, not a TypeError.
function readCookie(req: FastifyRequest, name: string): string | undefined {
  return (req.cookies as Partial<Record<string, string>> | undefined)?.[name];
}

/** passport-jwt extractor: the session cookie set by `setSessionCookies`. */
export function fromSessionCookie(req: FastifyRequest): string | null {
  return readCookie(req, SESSION_COOKIE) ?? null;
}

/** Cookie-authenticated unsafe requests must echo a CSRF token bound to the session. */
export function assertCsrf(req: FastifyRequest): void {
  const session = readCookie(req, SESSION_COOKIE);
  // Bearer requests are not CSRF-exposed: browsers never attach Authorization on their own.
  if (SAFE_METHODS.has(req.method) || req.headers.authorization || !session) return;
  const header = req.headers[CSRF_HEADER];
  if (
    typeof header !== 'string' ||
    header !== readCookie(req, CSRF_COOKIE) ||
    !verifyCsrfToken(header, session)
  ) {
    throw new ForbiddenException('CSRF token missing or invalid.');
  }
}

export function setSessionCookies(reply: FastifyReply, token: string): void {
  const options = {
    path: '/',
    secure: COOKIE_SECURE,
    sameSite: 'strict',
    maxAge: appConfig.JWT_EXPIRES_IN_SECONDS,
  } as const;
  void reply.setCookie(SESSION_COOKIE, token, { ...options, httpOnly: true });
  // Readable on purpose: the SPA echoes it back in the X-CSRF-Token header.
  void reply.setCookie(CSRF_COOKIE, createCsrfToken(token), { ...options, httpOnly: false });
}

export function clearSessionCookies(reply: FastifyReply): void {
  // Attributes must match, or browsers ignore the deletion of a __Host- cookie.
  const options = { path: '/', secure: COOKIE_SECURE, sameSite: 'strict' } as const;
  void reply.clearCookie(SESSION_COOKIE, { ...options, httpOnly: true });
  void reply.clearCookie(CSRF_COOKIE, options);
}
```

**4. `src/modules/auth/jwt.strategy.ts`** — import `fromSessionCookie` from `./auth.cookies` and read Bearer first, then the cookie:

```typescript
      // Bearer first (API clients), then the HttpOnly session cookie (browser clients).
      jwtFromRequest: ExtractJwt.fromExtractors([
        ExtractJwt.fromAuthHeaderAsBearerToken(),
        fromSessionCookie,
      ]),
```

**5. `src/modules/auth/jwt-auth.guard.ts`** — add this method (import `ExecutionContext` from `@nestjs/common`, `type FastifyRequest` from `fastify`, `assertCsrf` from `./auth.cookies`; keep any constructor/`handleRequest` that `templatecentral:add (logging)` added):

```typescript
  override canActivate(context: ExecutionContext) {
    assertCsrf(context.switchToHttp().getRequest<FastifyRequest>());
    return super.canActivate(context);
  }
```

**6. `src/modules/auth/auth.controller.ts`** — add the browser login and logout (merge `Res`, `ApiCookieAuth`, `ApiNoContentResponse`, `type FastifyReply`, `Throttle`/`minutes` and the two cookie helpers into the imports; add `@ApiCookieAuth()` next to `@ApiBearerAuth()` on `me`). `/auth/login` keeps returning the token for API clients; `/auth/session` returns 204 so the JWT never reaches JavaScript, and minting a fresh session + CSRF pair on every login also defeats session fixation:

```typescript
  @Post('session')
  @Throttle({ default: { ttl: minutes(15), limit: 3 } })
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Browser login — sets the HttpOnly session cookie' })
  @ApiNoContentResponse()
  async createSession(
    @Body() dto: LoginDto,
    @Res({ passthrough: true }) reply: FastifyReply
  ): Promise<void> {
    const { accessToken } = await this.authService.login(dto);
    setSessionCookies(reply, accessToken);
  }

  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Clear the session and CSRF cookies' })
  @ApiNoContentResponse()
  logout(@Res({ passthrough: true }) reply: FastifyReply): void {
    clearSessionCookies(reply);
  }
```

`/session` needs no CSRF token: its body must be JSON (Fastify answers 415 to a body with no Content-Type and hands `text/plain` to Zod as a string → 400 — the e2e test pins both), and a cross-origin JSON `fetch` must pass a CORS preflight the allowlist rejects — the custom-request-header defense OWASP lists for API endpoints. `@Throttle` applies once the Rate Limiting step below installs `@nestjs/throttler`.

**7. `test/auth-cookie.e2e-spec.ts`** — calls `setupSecurity`/`setupCors` like `main.ts` (suites that skip them still get a clean 401 from the guard):

```typescript
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { Controller, Post, UseGuards } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Test } from '@nestjs/testing';
import { AppModule } from '../src/app.module';
import { setupCors, setupSecurity } from '../src/config';
import { COOKIE_SECURE, CSRF_COOKIE, SESSION_COOKIE } from '../src/modules/auth/auth.cookies';
import { AuthService } from '../src/modules/auth/auth.service';
import { JwtAuthGuard } from '../src/modules/auth/jwt-auth.guard';

// A guarded unsafe route, so the CSRF check is exercised independently of feature modules.
@Controller('csrf-probe')
@UseGuards(JwtAuthGuard)
class CsrfProbeController {
  @Post()
  write() {
    return { ok: true };
  }
}

type SetCookie = string | string[] | undefined;

/** name=value pairs from Set-Cookie, ready for a Cookie request header. */
function cookieHeader(setCookie: SetCookie): string {
  return [setCookie ?? []]
    .flat()
    .map((c) => c.split(';')[0])
    .join('; ');
}

function cookieValue(setCookie: SetCookie, name: string): string {
  const pair = [setCookie ?? []].flat().find((c) => c.startsWith(`${name}=`)) ?? '';
  return decodeURIComponent(pair.split(';')[0].slice(name.length + 1));
}

describe('Auth cookie mode (e2e)', () => {
  let app: NestFastifyApplication;
  let setCookie: SetCookie;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
      controllers: [CsrfProbeController],
    })
      // Add the same .overrideProvider(...) calls your auth.e2e-spec.ts carries (database guides).
      .compile();
    app = moduleFixture.createNestApplication<NestFastifyApplication>(new FastifyAdapter());
    // Registers @fastify/cookie and CORS exactly as main.ts does.
    await setupSecurity(app);
    setupCors(app);
    await app.init();
    await app.getHttpAdapter().getInstance().ready();

    // Stand-in for AuthService.login (a stub until the database guide lands): any valid token
    // works for the cookie checks.
    const accessToken = await app
      .get(JwtService)
      .signAsync({ sub: 'user-1', email: 'a@example.com' });
    vi.spyOn(app.get(AuthService), 'login').mockResolvedValue({ accessToken, tokenType: 'bearer' });
    const res = await app.inject({
      method: 'POST',
      url: '/auth/session',
      payload: { email: 'a@example.com', password: 'x'.repeat(12) },
    });
    expect(res.statusCode).toBe(204);
    expect(res.body).toBe('');
    setCookie = res.headers['set-cookie'];
  });

  afterAll(async () => {
    await app.close();
  });

  it('sets an HttpOnly, SameSite=Strict session cookie and a readable CSRF cookie', () => {
    const cookies = [setCookie ?? []].flat();
    const session = cookies.find((c) => c.startsWith(`${SESSION_COOKIE}=`)) ?? '';
    const csrf = cookies.find((c) => c.startsWith(`${CSRF_COOKIE}=`)) ?? '';
    expect(session).toMatch(/HttpOnly/);
    expect(csrf).not.toMatch(/HttpOnly/);
    for (const cookie of [session, csrf]) {
      expect(cookie).toMatch(/SameSite=Strict/);
      expect(cookie).toMatch(/Path=\//);
      expect(/Secure/.test(cookie)).toBe(COOKIE_SECURE);
    }
  });

  it('authenticates GET /auth/me from the cookie alone', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/auth/me',
      headers: { cookie: cookieHeader(setCookie) },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: 'user-1', email: 'a@example.com', roles: [] });
  });

  it('rejects a cookie-authenticated POST without a valid CSRF header', async () => {
    const cookie = cookieHeader(setCookie);
    const missing = await app.inject({ method: 'POST', url: '/csrf-probe', headers: { cookie } });
    expect(missing.statusCode).toBe(403);
    const forged = await app.inject({
      method: 'POST',
      url: '/csrf-probe',
      headers: { cookie, 'x-csrf-token': 'forged.token' },
    });
    expect(forged.statusCode).toBe(403);
  });

  it('accepts a cookie-authenticated POST that echoes the CSRF cookie', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/csrf-probe',
      headers: {
        cookie: cookieHeader(setCookie),
        'x-csrf-token': cookieValue(setCookie, CSRF_COOKIE),
      },
    });
    expect(res.statusCode).toBe(201);
  });

  it('accepts Bearer without a CSRF header', async () => {
    const token = await app.get(JwtService).signAsync({ sub: 'user-2', email: 'b@example.com' });
    const res = await app.inject({
      method: 'POST',
      url: '/csrf-probe',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(201);
  });

  // CORS-simple bodies skip preflight: Fastify refuses a body with no Content-Type (415) and
  // hands text/plain to Zod as a string (400) — neither reaches AuthService.login.
  it.each([
    { headers: {}, status: 415 },
    { headers: { 'content-type': 'text/plain' }, status: 400 },
  ])('refuses a non-JSON login body with $status', async ({ headers, status }) => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/session',
      headers,
      payload: JSON.stringify({ email: 'a@example.com', password: 'x'.repeat(12) }),
    });
    expect(res.statusCode).toBe(status);
  });

  it('clears both cookies on logout', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/logout' });
    expect(res.statusCode).toBe(204);
    const cleared = [res.headers['set-cookie'] ?? []].flat();
    for (const name of [SESSION_COOKIE, CSRF_COOKIE]) {
      expect(cleared.find((c) => c.startsWith(`${name}=`))).toMatch(/Expires=Thu, 01 Jan 1970/);
    }
  });
});
```

### Rate Limiting (Required for Production)

Target: cap auth attempts at roughly 3 per 15 minutes per IP. Install `@nestjs/throttler`:

```bash
pnpm add @nestjs/throttler
```

Register globally in `AppModule` (import + guard) with a generous default — the global `ThrottlerGuard` applies this limit to EVERY endpoint, so the strict auth limit must NOT live here:

```typescript
import { ThrottlerModule, ThrottlerGuard, minutes } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';

@Module({
  imports: [
    ThrottlerModule.forRoot([{ ttl: minutes(1), limit: 100 }]),
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
```

Then tighten only the auth endpoints: in `auth.controller.ts`, import `{ Throttle, minutes } from '@nestjs/throttler'` and add this decorator directly under both `@Post('register')` and `@Post('login')`:

```typescript
  @Throttle({ default: { ttl: minutes(15), limit: 3 } })
```

> **`@Throttle` counts every request, not just failures.** A successful login consumes the same budget as a rejected one, so `limit: 3` means three total `/login` calls per IP per 15 minutes. Users behind a shared office NAT or mobile CGNAT share one bucket and will lock each other out — raise the limit for NAT-heavy audiences. To count only failures, subclass `ThrottlerGuard` and override `handleRequest` so the attempt is recorded after the handler resolves to a 401 rather than before it runs.

### Rules

- **JWT_SECRET must be kept secret** — never commit to version control; document only as a placeholder in `.env.example`.
- Always hash passwords with argon2id — never store plaintext. Use the `argon2` npm package. Memory-hard and resistant to GPU-based brute-force (OWASP recommendation; industry-standard minimum 12-character passwords).
- Browser SPA clients get cookie mode (above), never a token in `localStorage` — Bearer stays for non-browser clients.
- The `JwtStrategy.validate()` return value becomes `req.user` — extend it to return a full user object once you have a database.
- `JwtStrategy.validate()` returns `roles: []`, so every `RolesGuard` route denies until roles are loaded. Once a database is added, load the user's roles from it there, never from the token.
- Every handler that loads a record by id calls `assertOwner` (or filters the query by owner) before returning or changing it.
- **Rate limiting is mandatory for production** — add `@nestjs/throttler` before going live.
- **TRUST_PROXY must be set when behind a reverse proxy** — `ThrottlerGuard` uses `req.ip`, which Fastify only patches from `X-Forwarded-For` when `trustProxy` is active (set via `TRUST_PROXY` in the scaffold). Without it, all proxied requests share the proxy's IP and hit the same rate bucket. Set it to the trusted proxy IPs/CIDRs, comma-separated — one-hop: the ALB's VPC CIDR; two-hop: both the Traefik and ALB CIDRs. Fastify no longer accepts a numeric hop count (a number trusts nothing).

### Validate

```bash
pnpm check && pnpm build && pnpm test && pnpm test:e2e
```

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards

---

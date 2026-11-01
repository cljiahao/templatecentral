<!-- ref: add/auth/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS

Adds JWT authentication (Passport.js) to a templateCentral NestJS project.

> **Stub notice:** `AuthService` is intentionally incomplete — `register` and `login` throw `NotImplementedException` (501) until `templatecentral:add` (database) completes them.

### Dependencies

`argon2` is a native addon pnpm blocks by default. Uncomment the existing `# argon2: true` under `allowBuilds:` in `pnpm-workspace.yaml` — do not add a second `allowBuilds:` key (YAML drops the earlier one, losing the `lefthook`/`@scarf/scarf` entries):

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

Need `<!-- templateCentral: nestjs@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

#### 1. Create Auth Module Directory

Run `TC_PART=leaf TC_LEAF=add/auth/nestjs TC_TREE=template bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/auth/nestjs/template/` into the project per `<skill-dir>/auth/nestjs/template.manifest`, and writes nothing, ending with a `STOP:` line, when a path is in the way. It creates `src/modules/auth/` (flat — no subdirectories, matching the template's module structure) and the two test files of Step 13:
- module, controller, service, dto, `jwt.strategy`, `jwt-auth.guard`, `roles.decorator`, `roles.guard`, `ownership` (`.ts`)

#### 2. Define DTOs

**`src/modules/auth/auth.dto.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/auth.dto.ts` by the copy step; do not re-type it.

#### 3. Add Config

Add `JWT_SECRET` and `JWT_EXPIRES_IN_SECONDS` to `envSchema` in **`src/config/env.config.ts`** — validated at import, so a missing or short secret fails boot:

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

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/jwt.strategy.ts` by the copy step; do not re-type it.

#### 5. Create Auth Guard

**`src/modules/auth/jwt-auth.guard.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/jwt-auth.guard.ts` by the copy step; do not re-type it.

#### 6. Create Authorization Helpers

Deny-by-default role and ownership checks. `JwtAuthGuard` says who the caller is; these decide what the caller may touch.

**`src/modules/auth/roles.decorator.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/roles.decorator.ts` by the copy step; do not re-type it.

**`src/modules/auth/roles.guard.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/roles.guard.ts` by the copy step; do not re-type it.

**`src/modules/auth/ownership.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/ownership.ts` by the copy step; do not re-type it.

List `RolesGuard` after `JwtAuthGuard` so `req.user` is set before roles are checked. Use `assertOwner` on record-by-id handlers (see Rules):

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

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/auth.service.ts` by the copy step; do not re-type it.

#### 8. Create Auth Controller

**`src/modules/auth/auth.controller.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/auth.controller.ts` by the copy step; do not re-type it.

#### 9. Create Auth Module

**`src/modules/auth/auth.module.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/src/modules/auth/auth.module.ts` by the copy step; do not re-type it.

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

Vitest does not load `.env`, and `env.config.ts` now throws without `JWT_SECRET`. In **both** `vitest.config.ts` and `vitest.config.e2e.ts`, add under `test:`:

```typescript
    // Vitest does not load .env, and env.config.ts rejects missing required values at import.
    env: { JWT_SECRET: 'test'.repeat(8) },
```

**`test/auth.e2e-spec.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template/test/auth.e2e-spec.ts` by the copy step; do not re-type it.

**`test/modules/auth/authz.spec.ts`** — unit tests for the role guard and ownership check; no app boot needed:

Copied verbatim from `<skill-dir>/auth/nestjs/template/test/modules/auth/authz.spec.ts` by the copy step; do not re-type it.

### Browser Client (Cookie Mode)

**Apply when a browser SPA calls this API** — Vite + React auth (sends `credentials: 'include'` + `X-CSRF-Token`, never Bearer) or Next.js client components. Without it every `JwtAuthGuard` route answers that SPA with 401.

**Same-origin only:** the SPA reaches this API through a reverse proxy on its own origin (Vite `server.proxy`, nginx `location /api/`, or Next.js `rewrites()` — snippets in `templatecentral:standards (full-stack-pairing)`); `XSRF-TOKEN` is host-only, so from another host every non-GET 403s.

Design (OWASP CSRF + Session Management cheat sheets, RFC 10017 *OAuth 2.0 for Browser-Based Applications* §6.1 cookie rules): the JWT rides in an `HttpOnly; Secure; SameSite=Strict; Path=/` cookie named `__Host-session` (`session` in dev, where `Secure` is off for plain-http localhost) — never in JS-readable storage. Unsafe methods carry a **signed double-submit** CSRF token: the readable `XSRF-TOKEN` cookie holds `nonce.HMAC(key, session, nonce)`, the SPA echoes it in `X-CSRF-Token`, and the guard recomputes the HMAC against the session cookie — so a token injected from a sibling subdomain or another session fails. Bearer requests skip the check (browsers never attach `Authorization` themselves), so API clients are unaffected. Hand-rolled on `node:crypto` rather than `@fastify/csrf-protection`, whose `onRequest`-hook model does not compose with Nest guards.

Run `TC_PART=leaf TC_LEAF=add/auth/nestjs TC_TREE=template-cookie bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` first: it writes `src/modules/auth/auth.cookies.ts` (3) and `test/auth-cookie.e2e-spec.ts` (7) from `<skill-dir>/auth/nestjs/template-cookie/`.

**1. Install** `@fastify/cookie` (11.x, fastify 5):

```bash
pnpm add @fastify/cookie
```

**2. `src/config/setups/security.setup.ts`** — register the plugin at the top of `setupSecurity()` (before Helmet); `setupCors()` is unchanged (same-origin requests never preflight):

```typescript
import fastifyCookie from '@fastify/cookie';

  // Parses req.cookies and adds reply.setCookie — required by the auth session cookie.
  await fastify.register(fastifyCookie);
```

**3. `src/modules/auth/auth.cookies.ts`**:

Copied verbatim from `<skill-dir>/auth/nestjs/template-cookie/src/modules/auth/auth.cookies.ts` by the copy step; do not re-type it.

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

**6. `src/modules/auth/auth.controller.ts`** — add the browser login and logout (merge `Res`, `ApiCookieAuth`, `ApiNoContentResponse`, `type FastifyReply`, `Throttle`/`minutes` and the two cookie helpers into the imports; add `@ApiCookieAuth()` next to `@ApiBearerAuth()` on `me`). `/auth/login` still returns the token for API clients; `/auth/session` returns 204 so the JWT never reaches JavaScript, and a fresh session + CSRF pair per login defeats session fixation:

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

`/session` needs no CSRF token: its body must be JSON (Fastify answers 415 to a body with no Content-Type and hands `text/plain` to Zod as a string → 400 — the e2e test pins both), and a cross-origin JSON `fetch` must pass a CORS preflight the allowlist rejects (OWASP's custom-request-header defense). `@Throttle` applies once the Rate Limiting step below installs `@nestjs/throttler`.

**7. `test/auth-cookie.e2e-spec.ts`** — calls `setupSecurity`/`setupCors` like `main.ts` (suites that skip them still get a clean 401 from the guard):

Copied verbatim from `<skill-dir>/auth/nestjs/template-cookie/test/auth-cookie.e2e-spec.ts` by the copy step; do not re-type it.

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

> **`@Throttle` counts every request, not just failures** — `limit: 3` is three `/login` calls per IP per 15 minutes, and users behind a shared NAT/CGNAT share one bucket (raise it for such audiences). To count only failures, subclass `ThrottlerGuard` and record the attempt in `handleRequest` after the handler resolves to a 401, not before it runs.

### Rules

- Never commit `JWT_SECRET` — only a placeholder in `.env.example`.
- Hash passwords with argon2id (`argon2` package) — never store plaintext; minimum 12-character passwords.
- Browser SPAs use cookie mode, never a `localStorage` token; Bearer is for non-browser clients.
- `JwtStrategy.validate()`'s return becomes `req.user`; return a full user once a database exists.
- `JwtStrategy.validate()` returns `roles: []`, so every `RolesGuard` route denies until roles are loaded. Once a database is added, load the user's roles from it there, never from the token.
- Every record-by-id handler calls `assertOwner` (or filters by owner) first.
- Rate limiting (`@nestjs/throttler`) is mandatory before production.
- **TRUST_PROXY must be set when behind a reverse proxy** — `ThrottlerGuard` reads `req.ip`, which Fastify takes from `X-Forwarded-For` only with `trustProxy` (`TRUST_PROXY`); otherwise all requests share one bucket. Set comma-separated trusted CIDRs — one hop: the ALB's VPC CIDR; two hops: Traefik and ALB CIDRs. A numeric hop count trusts nothing.

### Validate

```bash
pnpm check && pnpm build && pnpm test && pnpm test:e2e
```

### After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.

---

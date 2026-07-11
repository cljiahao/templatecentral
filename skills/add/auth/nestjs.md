<!-- ref: add/auth/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS

Add JWT-based authentication to a NestJS project scaffolded from templateCentral using Passport.js.

> **Stub notice:** The `AuthService` created here is intentionally incomplete — both `register` and `login` throw `UnauthorizedException` until a database is available. Run `templatecentral:add` (database) after this skill to complete the integration.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### Dependencies

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

#### 2. Define DTOs

**`src/modules/auth/auth.dto.ts`**:

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const registerSchema = z.object({
  email: z.email(),
  // 12-char minimum — OWASP recommendation
  password: z.string().min(12),
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

#### 3. Add Config

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

Document in `.env.example`:
```
JWT_SECRET=<generate with: openssl rand -hex 32>
JWT_EXPIRES_IN=30m
```

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

#### 5. Create Auth Guard

**`src/modules/auth/jwt-auth.guard.ts`**:

```typescript
import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
```

#### 6. Create Auth Service

**`src/modules/auth/auth.service.ts`**:

```typescript
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

import type { RegisterDto, LoginDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(private readonly jwtService: JwtService) {}

  // Both methods are deliberate stubs (synchronous throws, unused params prefixed with _)
  // until templatecentral:add (database) replaces them with real implementations.
  register(_dto: RegisterDto) {
    throw new UnauthorizedException('Database integration required. Run templatecentral:add (database) to complete auth.');
  }

  login(_dto: LoginDto) {
    throw new UnauthorizedException('Database integration required. Run templatecentral:add (database) to complete auth.');
  }
}
```

#### 7. Create Auth Controller

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

#### 8. Create Auth Module

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

#### 9. Export from Modules Barrel

Add the auth module to `src/modules/index.ts`:

```typescript
export * from './auth/auth.module';
```

#### 10. Register in AppModule

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

#### 11. Protect Routes

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
import type { FastifyRequest } from 'fastify';

@UseGuards(JwtAuthGuard)
@Get('me')
getMe(@Req() req: FastifyRequest & { user: { id: string; email: string } }): { id: string; email: string } {
  // { id, email } from JwtStrategy.validate()
  return req.user;
}
```

### Rate Limiting (Required for Production)

Industry best practice: max 3 failed auth attempts per 15 minutes. Install `@nestjs/throttler`:

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

Then tighten only the auth endpoints with `@Throttle()` on the handlers in `auth.controller.ts`:

```typescript
import { Throttle, minutes } from '@nestjs/throttler';

  @Post('register')
  @Throttle({ default: { ttl: minutes(15), limit: 3 } })
  @ApiOperation({ summary: 'Register a new user' })
  register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Post('login')
  @Throttle({ default: { ttl: minutes(15), limit: 3 } })
  @ApiOperation({ summary: 'Authenticate and receive a JWT token' })
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }
```

### Rules

- **JWT_SECRET must be kept secret** — never commit to version control; document only as a placeholder in `.env.example`.
- Always hash passwords with argon2id — never store plaintext. Use the `argon2` npm package. Memory-hard and resistant to GPU-based brute-force (OWASP recommendation; industry-standard minimum 12-character passwords).
- The `JwtStrategy.validate()` return value becomes `req.user` — extend it to return a full user object once you have a database.
- **Rate limiting is mandatory for production** — add `@nestjs/throttler` before going live.
- **TRUST_PROXY must be set when behind a reverse proxy** — `ThrottlerGuard` uses `req.ip`, which Fastify only patches from `X-Forwarded-For` when `trustProxy` is active (set via `TRUST_PROXY` in the scaffold). Without it, all proxied requests share the proxy's IP and hit the same rate bucket. Set `TRUST_PROXY=1` (one-hop: ALB → App) or `TRUST_PROXY=2` (two-hop: ALB → Traefik → App); the scaffold converts numeric strings to integers automatically.

### Validate

```bash
pnpm build    # zero compile errors
pnpm test     # auth tests pass
```

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards

---

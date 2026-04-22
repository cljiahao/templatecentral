---
name: add-auth
description: Use when the user wants to add authentication, JWT tokens, password hashing, or user login/registration to a NestJS project.
---

# Add Auth to NestJS

Add JWT-based authentication to a NestJS project scaffolded from templateCentral using Passport.js.

## Dependencies

```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt bcrypt
pnpm add -D @types/passport-jwt @types/bcrypt
```

## Steps

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
  email: z.string().email(),
  password: z.string().min(8),
  name: z.string().min(1),
});

const loginSchema = z.object({
  email: z.string().email(),
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

And add to `.env`:
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
import * as bcrypt from 'bcrypt';

import type { RegisterDto, LoginDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(private readonly jwtService: JwtService) {}

  async register(dto: RegisterDto) {
    const hashedPassword = await bcrypt.hash(dto.password, 10);
    // TODO: persist user to database
    const user = { id: 'generated-id', email: dto.email, name: dto.name, hashedPassword };
    return { id: user.id, email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    // TODO: look up user by email from database
    // const user = await this.usersRepository.findByEmail(dto.email);
    // const isValid = user && await bcrypt.compare(dto.password, user.hashedPassword);
    // if (!isValid) throw new UnauthorizedException('Invalid credentials');
    // const payload = { sub: user.id, email: user.email };
    // return { accessToken: this.jwtService.sign(payload), tokenType: 'bearer' as const };
    throw new UnauthorizedException('Replace with real user lookup');
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

Add to `.env`:
- `JWT_SECRET` — Random string for JWT signing (generate with `openssl rand -hex 32`)
- `JWT_EXPIRES_IN` — Token expiry duration (default: `30m`)

Also add placeholder entries to `.env.example`:
```
JWT_SECRET=<generate with: openssl rand -hex 32>
JWT_EXPIRES_IN=30m
```

## Rules

- **JWT_SECRET must be kept secret** — never commit to version control; document only as a placeholder in `.env.example`.
- Always hash passwords with `bcrypt` — never store plaintext.
- The `JwtStrategy.validate()` return value becomes `req.user` — extend it to return a full user object once you have a database.

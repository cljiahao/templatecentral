<!-- ref: add/database/typescript/nestjs-drizzle.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Drizzle (SQL, standard auth). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Drizzle (SQL)

> **Drizzle ORM v1**: v1.0 is still pre-release (RC stage) — pin the RC exactly. The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.

#### A1. Install Dependencies

Read the exact RC from the plugin's version SSOT — `cat "<skill-dir>/../../.claude/rules/nestjs.md"` (the scaffolded project has no copy) — and install it exactly; never the floating `@rc` tag, which resolves to a different RC on every install:

```bash
pnpm add --save-exact drizzle-orm@<exact-rc-from-rules> postgres
pnpm add -D --save-exact drizzle-kit@<exact-rc-from-rules>
```

Both packages must be on the same RC — a `drizzle-kit` that disagrees with `drizzle-orm` generates migrations the runtime cannot read.

`drizzle-kit` pulls in `esbuild`, whose install script pnpm 12 blocks (`ERR_PNPM_IGNORED_BUILDS`). Its platform binary ships as an optional dependency, so the script is not needed — add under the existing `allowBuilds:` in `pnpm-workspace.yaml`:

```yaml
  esbuild: false
```

#### A2. Add Database Scripts

Add to `package.json`:

```json
{
  "scripts": {
    "db:generate": "drizzle-kit generate",
    "db:migrate": "drizzle-kit migrate",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio"
  }
}
```

#### A3. Create Drizzle Config

**`drizzle.config.ts`** (project root):

```ts
// drizzle-kit runs outside main.ts and does not read .env on its own.
import 'dotenv/config';
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './src/database/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});
```

> `drizzle.config.ts` reads `process.env` directly — it runs as a standalone CLI command outside NestJS, so it cannot use `serviceConfig`. Against any non-local database, end that `DATABASE_URL` with `?sslmode=verify-full` so `drizzle-kit migrate` verifies the server certificate (`require` encrypts without verifying identity).

#### A4. Define Schema

**`src/database/schema.ts`**:

```typescript
import { pgTable, text, timestamp } from 'drizzle-orm/pg-core';

export const users = pgTable('users', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdateFn(() => new Date()),
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
```

#### A5. Create DrizzleService

**`src/database/drizzle.service.ts`**:

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { drizzle } from 'drizzle-orm/postgres-js';
import { sql } from 'drizzle-orm';
import postgres from 'postgres';

import { appConfig, serviceConfig } from '../config/env.config';

@Injectable()
export class DrizzleService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DrizzleService.name);
  private readonly client: ReturnType<typeof postgres>;
  // In v1 the first type parameter of `drizzle` is TRelations, not the schema —
  // tables are passed per query (`.from(users)`), so no schema generic is needed.
  readonly db: ReturnType<typeof drizzle>;

  constructor() {
    this.client = postgres(serviceConfig.DATABASE_URL, {
      // postgres.js defaults to plaintext. Local Docker Postgres serves no TLS, so only dev
      // skips it; 'verify-full' checks the certificate chain and hostname.
      ssl: appConfig.ENVIRONMENT === 'dev' ? false : 'verify-full',
    });
    this.db = drizzle({ client: this.client });
  }

  async onModuleInit() {
    try {
      await this.db.execute(sql`SELECT 1`);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.client.end();
  }
}
```

#### A6. Create DatabaseModule

**`src/database/database.module.ts`**:

```typescript
import { Global, Module } from '@nestjs/common';

import { DrizzleService } from './drizzle.service';

@Global()
@Module({
  providers: [DrizzleService],
  exports: [DrizzleService],
})
export class DatabaseModule {}
```

#### A7. Register in AppModule

Import `DatabaseModule` in `src/app.module.ts`:

```typescript
import { DatabaseModule } from './database/database.module';

@Module({
  imports: [
    DatabaseModule,
    // ...existing modules
  ],
})
export class AppModule {}
```

#### A8. Configure Environment

Add `DATABASE_URL` to `envSchema` in `src/config/env.config.ts` — validated at import time, so boot fails loudly if it's missing instead of surfacing as a runtime `undefined`:

```typescript
const envSchema = z.object({
  // ... existing fields ...
  DATABASE_URL: z.string().min(1),
});
```

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_URL: env.DATABASE_URL,
};
```

Add to `.env` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

#### A9. Generate & Run Migrations

```bash
pnpm db:generate
pnpm db:migrate
```

For rapid local iteration, `pnpm db:push` applies the schema directly without migration files (dev only — never use against production).

#### A10. Usage

Inject `DrizzleService` in any module's service:

```typescript
import { Injectable } from '@nestjs/common';
import { eq } from 'drizzle-orm';

import { DrizzleService } from '../../database/drizzle.service';
import { users } from '../../database/schema';

@Injectable()
export class UserService {
  constructor(private readonly drizzle: DrizzleService) {}

  findAll() {
    return this.drizzle.db.select().from(users);
  }

  findById(id: string) {
    return this.drizzle.db.select().from(users).where(eq(users.id, id)).then((r) => r[0] ?? null);
  }

  create(data: { email: string; name: string }) {
    return this.drizzle.db.insert(users).values(data).returning();
  }
}
```

#### A11. Keep Tests Runnable Without a Database

`env.config.ts` now throws at import without `DATABASE_URL`, and Vitest does not load `.env`. Add it to the `test.env` object in **both** `vitest.config.ts` and `vitest.config.e2e.ts` (create the object if `add (auth)` has not):

```typescript
    // postgres.js connects lazily, so this placeholder is never dialled unless a test queries.
    env: { DATABASE_URL: 'postgresql://localhost:5432/test' },
```

`DrizzleService.onModuleInit` probes the database, so every e2e suite that boots `AppModule` without one (`test/app.e2e-spec.ts`, `test/auth.e2e-spec.ts`, …) overrides it:

```typescript
import { DrizzleService } from '../src/database/drizzle.service';

    const moduleFixture = await Test.createTestingModule({ imports: [AppModule] })
      // No database in this suite: skip DrizzleService's connection probe.
      .overrideProvider(DrizzleService)
      .useValue({})
      .compile();
```

Suites that exercise real queries run against a disposable Postgres (CI service container) with `DATABASE_URL` set in the job env, which `test.env` does not override.

#### A12. Validate

```bash
pnpm db:generate && pnpm check && pnpm build && pnpm test && pnpm test:e2e
```

Confirm the migration file was generated and every command passes.

> **Need to upgrade to high compliance later?** Tell me *"migrate database to compliance"* and I'll handle the switch to Kysely + AWS IAM.

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place `DrizzleService` and `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. Use `pnpm db:push` in development only — never against production. Migration files live in `drizzle/` at the project root; commit them to version control. Does not include a native IAM token-fetching variant — use Kysely if IAM auth is required.

---

## Completing Auth Integration

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations.

**Step A — Add `hashedPassword` to `src/database/schema.ts`**

Add the `hashedPassword` column to the existing `users` table (add only the highlighted line — preserve any other tables in the file):

```typescript
export const users = pgTable('users', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  hashedPassword: text('hashed_password').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdateFn(() => new Date()),
});
```

Then run:

```bash
pnpm db:generate
pnpm db:migrate
```

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import { eq } from 'drizzle-orm';

import { DrizzleService } from '../../database/drizzle.service';
import { users } from '../../database/schema';
import type { LoginDto, RegisterDto } from './auth.dto';

// Verified on the miss path so an unknown email costs the same as a wrong
// password — without it, response timing leaks which accounts exist. Hashed at
// startup with the same defaults as real passwords so the cost matches exactly.
const DUMMY_HASH = argon2.hash(randomUUID());

const PG_UNIQUE_VIOLATION = '23505';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly drizzle: DrizzleService,
  ) {}

  async register(dto: RegisterDto) {
    // argon2id by default
    const hashedPassword = await argon2.hash(dto.password);
    try {
      const [user] = await this.drizzle.db
        .insert(users)
        .values({ email: dto.email, name: dto.name, hashedPassword })
        .returning({ id: users.id, email: users.email, name: users.name });
      return user;
    } catch (error) {
      // The unique index, not a SELECT-then-INSERT pre-check, is race-free under concurrent
      // sign-ups. Drizzle v1 wraps driver errors in DrizzleQueryError; the pg code is on `cause`.
      if ((error as { cause?: { code?: string } }).cause?.code === PG_UNIQUE_VIOLATION) {
        throw new ConflictException('Email already registered.');
      }
      throw error;
    }
  }

  async login(dto: LoginDto) {
    const [user] = await this.drizzle.db
      .select()
      .from(users)
      .where(eq(users.email, dto.email))
      .limit(1);
    const passwordOk = await argon2.verify(
      user?.hashedPassword ?? (await DUMMY_HASH),
      dto.password,
    );
    if (!user || !passwordOk) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return {
      accessToken: this.jwtService.sign({ sub: user.id, email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — `src/modules/auth/auth.module.ts` requires no changes**

`DrizzleService` is exported by the `@Global()` `DatabaseModule` and is injectable throughout the application without listing it in `AuthModule.providers`. Confirm `DatabaseModule` is registered in `AppModule` (the scaffold handles this).

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
<!-- ref: add/database/typescript/nestjs-drizzle.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Drizzle (SQL, standard auth). Do not invoke this file directly. -->
## NestJS + Drizzle (SQL)

> **Drizzle ORM v1**: v1.0 is still pre-release (RC stage). Pin the current v1 RC exactly in `package.json` (see `.claude/rules/nestjs.md`). The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.

#### A1. Install Dependencies

```bash
pnpm add drizzle-orm@rc postgres
pnpm add -D drizzle-kit
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
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './src/database/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});
```

> `drizzle.config.ts` reads `process.env` directly — it runs as a standalone CLI command outside NestJS, so it cannot use `serviceConfig`.

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

import { serviceConfig } from '../config/env.config';
import * as schema from './schema';

@Injectable()
export class DrizzleService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DrizzleService.name);
  private readonly client: ReturnType<typeof postgres>;
  readonly db: ReturnType<typeof drizzle<typeof schema>>;

  constructor() {
    this.client = postgres(serviceConfig.DATABASE_URL);
    this.db = drizzle(this.client, { schema });
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

Add `DATABASE_URL` to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_URL: process.env.DATABASE_URL!,
};
```

Add to `.env` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

**Add a startup guard in `src/main.ts`** — the `!` assertion is erased at compile time and does NOT throw at runtime if the variable is missing:

```typescript
async function bootstrap() {
  if (!serviceConfig.DATABASE_URL) {
    throw new Error('DATABASE_URL environment variable is required');
  }
  // ... rest of bootstrap
}
```

#### A9. Generate & Run Migrations

```bash
pnpm db:generate  # generate SQL migration files from schema
pnpm db:migrate   # apply pending migrations to the database
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

> Import `eq` from `drizzle-orm`: `import { eq } from 'drizzle-orm';`

#### A11. Validate

```bash
pnpm db:generate && pnpm build && pnpm test
```

Confirm the migration file was generated, build succeeds, and all tests pass.

> **AWS IAM auth**: Drizzle does not include a native IAM token-fetching variant. If AWS IAM database authentication is required, use **Kysely** (select Kysely when prompted) instead.

---

> **Need to upgrade to high compliance later?** Tell me *"migrate database to compliance"* and I'll handle the switch to Kysely + AWS IAM.

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place `DrizzleService` and `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. Use `pnpm db:push` in development only — never against production. Migration files live in `drizzle/` at the project root; commit them to version control. Add `*.db` and `*.db-journal` to `.gitignore` for SQLite. Does not include a native IAM token-fetching variant — use Kysely if IAM auth is required.

---

## Completing Auth Integration

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the in-memory stubs with real database-backed implementations.

**Step A — Add `hashedPassword` to `src/database/schema.ts`**

Add the `hashedPassword` column to the existing `users` table (add only the highlighted line — preserve any other tables in the file):

```typescript
export const users = pgTable('users', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  hashedPassword: text('hashed_password').notNull(), // add this line
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
import * as argon2 from 'argon2';
import { eq } from 'drizzle-orm';

import { DrizzleService } from '../../database/drizzle.service';
import { users } from '../../database/schema';
import type { LoginDto, RegisterDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly drizzle: DrizzleService,
  ) {}

  async register(dto: RegisterDto) {
    const [existing] = await this.drizzle.db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.email, dto.email))
      .limit(1);
    if (existing) throw new ConflictException('Email already registered.');

    const hashedPassword = await argon2.hash(dto.password);  // argon2id by default
    const [user] = await this.drizzle.db
      .insert(users)
      .values({ email: dto.email, name: dto.name, hashedPassword })
      .returning({ id: users.id, email: users.email, name: users.name });
    return user;
  }

  async login(dto: LoginDto) {
    const [user] = await this.drizzle.db
      .select()
      .from(users)
      .where(eq(users.email, dto.email))
      .limit(1);
    if (!user || !(await argon2.verify(user.hashedPassword, dto.password))) {
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
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards
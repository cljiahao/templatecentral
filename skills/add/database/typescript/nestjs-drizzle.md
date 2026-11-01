<!-- ref: add/database/typescript/nestjs-drizzle.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Drizzle (SQL, standard auth). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Drizzle (SQL)

> **Drizzle ORM v1** is pre-release — pin the RC exactly. v1 moved `casing` from `drizzle()` to schema-level `snakeCase`/`camelCase` helpers ([v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide)).

#### A1. Install Dependencies

Read the exact RC from `cat "<skill-dir>/../../.claude/rules/nestjs.md"` (projects have no copy) and install it exactly, never the floating `@rc` tag:

```bash
pnpm add --save-exact drizzle-orm@<exact-rc-from-rules> postgres
pnpm add -D --save-exact drizzle-kit@<exact-rc-from-rules>
```

Keep both on the same RC — a mismatched `drizzle-kit` writes migrations the runtime cannot read.

`drizzle-kit` pulls in `esbuild`, whose install script pnpm 12 blocks (`ERR_PNPM_IGNORED_BUILDS`). Its binary ships as an optional dependency, so deny the script under the existing `allowBuilds:` in `pnpm-workspace.yaml`:

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

Run `TC_PART=leaf TC_LEAF=add/database/typescript/nestjs-drizzle bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/typescript/nestjs-drizzle/template/` (listed in `<skill-dir>/database/typescript/nestjs-drizzle/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`drizzle.config.ts`** (project root):

Copied verbatim from `<skill-dir>/database/typescript/nestjs-drizzle/template/drizzle.config.ts` by the copy step; do not re-type it.

> `drizzle.config.ts` reads `process.env` directly — it runs as a standalone CLI command outside NestJS, so it cannot use `serviceConfig`. Against any non-local database, end that `DATABASE_URL` with `?sslmode=verify-full` so `drizzle-kit migrate` verifies the server certificate (`require` encrypts without verifying identity).

#### A4. Define Schema

**`src/database/schema.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nestjs-drizzle/template/src/database/schema.ts` by the copy step; do not re-type it.

#### A5. Create DrizzleService

**`src/database/drizzle.service.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nestjs-drizzle/template/src/database/drizzle.service.ts` by the copy step; do not re-type it.

#### A6. Create DatabaseModule

**`src/database/database.module.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nestjs-drizzle/template/src/database/database.module.ts` by the copy step; do not re-type it.

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

Add `DATABASE_URL` to `envSchema` in `src/config/env.config.ts` — validated at import, so boot fails when it is missing:

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

`pnpm db:push` applies the schema without migration files — dev only, never production.

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

Vitest does not load `.env`, and `env.config.ts` now throws without `DATABASE_URL` — add it to `test.env` in **both** `vitest.config.ts` and `vitest.config.e2e.ts` (create the object if needed):

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

Suites with real queries use a disposable Postgres (CI service container); the job's `DATABASE_URL` wins over `test.env`.

#### A12. Validate

```bash
pnpm db:generate && pnpm check && pnpm build && pnpm test && pnpm test:e2e
```

Confirm the migration file was generated and every command passes.

> High compliance later: `templatecentral:migrate` (database) switches to Kysely + AWS IAM.

---

## Rules

- **Opt-in only** — add a database only on request.
- **Default to password auth** — use AWS SDK packages and IAM variants only when the user requires AWS IAM.
- `DatabaseModule` is `@Global()` so modules need not re-import it.
- Place `DrizzleService` and `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. `pnpm db:push` is dev-only, never production. Commit the migrations in `drizzle/`. No IAM variant — use Kysely for IAM auth.

---

## Completing Auth Integration

> **Only if `templatecentral:add` (auth) ran first** — replaces its 501 stubs with database-backed code.

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

`DrizzleService` comes from the `@Global()` `DatabaseModule` — no need to list it in `AuthModule.providers`; confirm `DatabaseModule` is in `AppModule`.

---

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.
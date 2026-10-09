<!-- ref: add/database/typescript/nestjs-kysely.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Kysely (SQL, supports standard + AWS IAM auth). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Kysely (SQL)

Kysely is a type-safe SQL query builder with full SQL control and minimal overhead. It defaults to standard password authentication. If the user requires AWS IAM auth, see the IAM variant below.

#### B1. Install Dependencies

```bash
pnpm add kysely pg
pnpm add -D kysely-codegen @types/pg tsx
```

Add a migration script to `package.json`:

```json
{
  "scripts": {
    "migrate": "tsx src/database/migrate.ts"
  }
}
```

#### B2. Create KyselyService

> **Complete B7 (Configure Environment) before this step** — `serviceConfig.DATABASE_URL` must be defined before creating the service.

**`src/database/kysely.service.ts`**:

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { Kysely, PostgresDialect, sql } from 'kysely';
import { Pool } from 'pg';

import { appConfig, serviceConfig } from '../config/env.config';
import type { Database } from './types';

@Injectable()
export class KyselyService extends Kysely<Database> implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KyselyService.name);

  constructor() {
    const pool = new Pool({
      connectionString: serviceConfig.DATABASE_URL,
      max: 10,
      // node-postgres does NOT negotiate TLS on its own. Without this the password and
      // every row travel in plaintext. Local Docker Postgres serves no TLS, so it is
      // disabled in dev only — never for a managed/remote database.
      ssl: appConfig.ENVIRONMENT === 'dev' ? false : { rejectUnauthorized: true },
    });

    super({ dialect: new PostgresDialect({ pool }) });
  }

  async onModuleInit() {
    try {
      await sql`SELECT 1`.execute(this);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.destroy();
  }
}
```

> **TLS against a managed Postgres.** `rejectUnauthorized: true` verifies the server
> certificate against Node's default trust store. Providers whose certs chain to a public
> CA (Neon, Supabase, most Azure/GCP endpoints) work as-is. **AWS RDS does not** — its
> certs chain to the Amazon RDS root CA, which Node does not ship, so verification fails
> with `SELF_SIGNED_CERT_IN_CHAIN`. Install the CA bundle as shown in the IAM variant
> below rather than reaching for `rejectUnauthorized: false`, which disables
> authentication entirely and leaves the connection open to MITM.
>
> Appending `?sslmode=require` to `DATABASE_URL` is **not** a substitute: `require` only
> asks for encryption, it does not verify the server's identity.

##### IAM Auth Variant

If the user requires AWS IAM authentication, install the additional package:

```bash
pnpm add @aws-sdk/rds-signer
```

**Download the AWS RDS CA bundle first.** RDS server certificates chain to the Amazon RDS
root CA, which is not in Node's default trust store — without the bundle, TLS verification
fails with `SELF_SIGNED_CERT_IN_CHAIN` and the tempting "fix" (`rejectUnauthorized: false`)
silently downgrades the connection to unauthenticated TLS.

```bash
mkdir -p certs
curl -fsSL -o certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Commit `certs/rds-global-bundle.pem` (it is a public certificate, not a secret) or bake it
into the Docker image, and add `RDS_CA_BUNDLE_PATH=certs/rds-global-bundle.pem` to `.env`
and `.env.example`. In a container, `NODE_EXTRA_CA_CERTS=/app/certs/rds-global-bundle.pem`
is an equivalent process-wide alternative to the explicit `ca` option below.

Replace the entire contents of `kysely.service.ts` with:

```typescript
import { readFileSync } from 'node:fs';

import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { Kysely, PostgresDialect, sql } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

@Injectable()
export class KyselyService extends Kysely<Database> implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KyselyService.name);

  constructor() {
    const signer = new Signer({
      hostname: serviceConfig.DATABASE_HOST,
      port: serviceConfig.DATABASE_PORT,
      username: serviceConfig.DATABASE_USER,
    });

    const pool = new Pool({
      host: serviceConfig.DATABASE_HOST,
      port: serviceConfig.DATABASE_PORT,
      user: serviceConfig.DATABASE_USER,
      database: serviceConfig.DATABASE_NAME,
      password: () => signer.getAuthToken(),
      // The `ca` is required: without the Amazon RDS root CA, `rejectUnauthorized: true`
      // cannot build a chain and every connection fails with SELF_SIGNED_CERT_IN_CHAIN.
      ssl: {
        rejectUnauthorized: true,
        ca: readFileSync(serviceConfig.RDS_CA_BUNDLE_PATH, 'utf8'),
      },
      max: 10,
    });

    super({ dialect: new PostgresDialect({ pool }) });
  }

  async onModuleInit() {
    try {
      await sql`SELECT 1`.execute(this);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.destroy();
  }
}
```

> **IAM fields replace `DATABASE_URL`** — remove `DATABASE_URL` from both `envSchema` and `serviceConfig` when using IAM auth.

Add IAM fields to `envSchema` in `src/config/env.config.ts` — validated at import time, so boot fails loudly if a required field is missing instead of surfacing as a runtime `undefined`:

```typescript
const envSchema = z.object({
  // ... existing fields ...
  DATABASE_HOST: z.string().min(1),
  DATABASE_PORT: z.coerce.number().int().min(1).max(65535).default(5432),
  DATABASE_USER: z.string().min(1),
  DATABASE_NAME: z.string().min(1),
  RDS_CA_BUNDLE_PATH: z.string().min(1).default('certs/rds-global-bundle.pem'),
});
```

Then map the validated fields into `serviceConfig`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_HOST: env.DATABASE_HOST,
  DATABASE_PORT: env.DATABASE_PORT,
  DATABASE_USER: env.DATABASE_USER,
  DATABASE_NAME: env.DATABASE_NAME,
  RDS_CA_BUNDLE_PATH: env.RDS_CA_BUNDLE_PATH,
};
```

IAM environment variables (add to `.env` and `.env.example`):

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
RDS_CA_BUNDLE_PATH=certs/rds-global-bundle.pem
```

> IAM auth does not use a password — `@aws-sdk/rds-signer` generates a short-lived token automatically from the instance's IAM role.

> **Apply the same pool config to the migration runner.** `src/database/migrate.ts` (B6) builds
> its own `Pool` from `serviceConfig.DATABASE_URL`, which no longer exists under IAM — give it the
> same `Signer` + `ssl: { rejectUnauthorized: true, ca: readFileSync(...) }` options as the service
> above, or `pnpm migrate` fails to connect while the app itself works.

#### B3. Define Database Types

**`src/database/types.ts`**:

```typescript
import type { Generated, Insertable, Selectable, Updateable } from 'kysely';

export interface Database {
  users: UsersTable;
}

export interface UsersTable {
  id: Generated<string>;
  email: string;
  name: string;
  created_at: Generated<Date>;
  updated_at: Generated<Date>;
}

export type User = Selectable<UsersTable>;
export type NewUser = Insertable<UsersTable>;
export type UserUpdate = Updateable<UsersTable>;
```

> **Tip**: After the database exists, run `pnpm exec kysely-codegen` to auto-generate types from the live schema instead of maintaining them manually.

#### B4. Create DatabaseModule

**`src/database/database.module.ts`**:

```typescript
import { Global, Module } from '@nestjs/common';

import { KyselyService } from './kysely.service';

@Global()
@Module({
  providers: [KyselyService],
  exports: [KyselyService],
})
export class DatabaseModule {}
```

#### B5. Register in AppModule

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

#### B6. Create First Migration

**`src/database/migrations/001_initial.ts`**:

```typescript
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable('users')
    .addColumn('id', 'text', (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()::text`))
    .addColumn('email', 'text', (col) => col.notNull().unique())
    .addColumn('name', 'text', (col) => col.notNull())
    .addColumn('created_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .addColumn('updated_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable('users').execute();
}
```

Create a migration runner at **`src/database/migrate.ts`**:

```typescript
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { Kysely, PostgresDialect } from 'kysely';
// Migration classes live under the kysely/migration subpath — the root export's
// FileMigrationProvider/Migrator are typed as compile-time redirects to this subpath.
import { FileMigrationProvider, Migrator } from 'kysely/migration';
import { Pool } from 'pg';

import { appConfig, serviceConfig } from '../config/env.config';
import type { Database } from './types';

async function migrate() {
  const db = new Kysely<Database>({
    dialect: new PostgresDialect({
      pool: new Pool({
        connectionString: serviceConfig.DATABASE_URL,
        // Same TLS policy as KyselyService — migrations carry credentials too.
        ssl: appConfig.ENVIRONMENT === 'dev' ? false : { rejectUnauthorized: true },
      }),
    }),
  });

  const migrator = new Migrator({
    db,
    provider: new FileMigrationProvider({
      fs,
      path,
      migrationFolder: path.join(__dirname, 'migrations'),
    }),
  });

  const { results, error } = await migrator.migrateToLatest();
  results?.forEach((r) => {
    if (r.status === 'Success') console.log(`Migration "${r.migrationName}" executed successfully`);
    else if (r.status === 'Error') console.error(`Migration "${r.migrationName}" failed`);
  });

  if (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }

  await db.destroy();
}

// Without the catch, a rejected promise leaves the exit code at 0 and CI reports a
// failed migration as a passing step.
migrate().catch((e) => {
  console.error(e);
  process.exit(1);
});
```

Run migrations with: `pnpm migrate`

#### B7. Configure Environment

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

#### B8. Usage

Inject `KyselyService` in any module's service:

```typescript
import { Injectable } from '@nestjs/common';

import { KyselyService } from '../../database/kysely.service';

@Injectable()
export class UserService {
  constructor(private readonly db: KyselyService) {}

  // Explicit columns, not selectAll(): once auth lands, users carries hashed_password.
  private static readonly PUBLIC_COLUMNS = ['id', 'email', 'name', 'created_at'] as const;

  findAll() {
    return this.db.selectFrom('users').select(UserService.PUBLIC_COLUMNS).execute();
  }

  findById(id: string) {
    return this.db
      .selectFrom('users')
      .select(UserService.PUBLIC_COLUMNS)
      .where('id', '=', id)
      .executeTakeFirst();
  }

  create(data: { email: string; name: string }) {
    return this.db
      .insertInto('users')
      .values(data)
      .returning(UserService.PUBLIC_COLUMNS)
      .executeTakeFirstOrThrow();
  }
}
```

#### B9. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place `KyselyService` and `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Kysely**: Write manual `up`/`down` migration files in `src/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant constructor — no query code changes needed.

---

## Completing Auth Integration

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations.

**Step A — Update `src/database/types.ts` and add migration**

Add `hashed_password` to `UsersTable`:

```typescript
import type { Generated, Insertable, Selectable, Updateable } from 'kysely';

export interface Database {
  users: UsersTable;
}

export interface UsersTable {
  id: Generated<string>;
  email: string;
  name: string;
  hashed_password: string;
  created_at: Generated<Date>;
  updated_at: Generated<Date>;
}

export type User = Selectable<UsersTable>;
export type NewUser = Insertable<UsersTable>;
export type UserUpdate = Updateable<UsersTable>;
```

**If `001_initial.ts` has not been applied yet:** add `hashed_password text NOT NULL` directly to the `createTable` call in `001_initial.ts`.

**If `001_initial.ts` was already applied** (users table exists in the DB), create `src/database/migrations/002_add_auth.ts`:

```typescript
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .alterTable('users')
    .addColumn('hashed_password', 'text', (col) => col.notNull().defaultTo(''))
    .execute();
  // Remove the temporary default — hashed_password must not have a default in production
  await sql`ALTER TABLE users ALTER COLUMN hashed_password DROP DEFAULT`.execute(db);
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.alterTable('users').dropColumn('hashed_password').execute();
}
```

Run: `pnpm migrate`

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';

import { KyselyService } from '../../database/kysely.service';
import type { LoginDto, RegisterDto } from './auth.dto';

// Verified on the miss path so an unknown email costs the same as a wrong
// password — without it, response timing leaks which accounts exist. Hashed at
// startup with the same defaults as real passwords so the cost matches exactly.
const DUMMY_HASH = argon2.hash(randomUUID());

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly db: KyselyService,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.db
      .selectFrom('users')
      .select('id')
      .where('email', '=', dto.email)
      .executeTakeFirst();
    if (existing) throw new ConflictException('Email already registered.');

    // argon2id by default
    const hashedPassword = await argon2.hash(dto.password);
    const user = await this.db
      .insertInto('users')
      .values({ email: dto.email, name: dto.name, hashed_password: hashedPassword })
      .returning(['id', 'email', 'name'])
      .executeTakeFirstOrThrow();
    return user;
  }

  async login(dto: LoginDto) {
    const user = await this.db
      .selectFrom('users')
      .selectAll()
      .where('email', '=', dto.email)
      .executeTakeFirst();
    const passwordOk = await argon2.verify(
      // `||`, not `??`: rows backfilled by 002_add_auth hold '' — argon2.verify throws on it.
      user?.hashed_password || (await DUMMY_HASH),
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

`KyselyService` is exported by the `@Global()` `DatabaseModule` and is injectable throughout the application without listing it in `AuthModule.providers`.

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
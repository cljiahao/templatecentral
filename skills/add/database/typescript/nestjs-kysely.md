<!-- ref: add/database/typescript/nestjs-kysely.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Kysely (SQL, supports standard + AWS IAM auth). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Kysely (SQL)

Kysely is a type-safe SQL query builder with full SQL control and minimal overhead. It defaults to standard password authentication. AWS IAM auth and auth-stub completion live in sibling add-ons (`nestjs-kysely-iam.md`, `nestjs-kysely-auth.md`) that the router loads alongside this guide only when needed.

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
> with `SELF_SIGNED_CERT_IN_CHAIN`. Install the CA bundle rather than reaching for
> `rejectUnauthorized: false`, which disables authentication entirely and leaves the
> connection open to MITM:
>
> ```bash
> mkdir -p certs
> curl -fsSL -o certs/rds-global-bundle.pem \
>   https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
> ```
>
> Commit it (a public certificate, not a secret) or bake it into the image, and set
> `RDS_CA_BUNDLE_PATH=certs/rds-global-bundle.pem` in `.env` and `.env.example`. Pass it as
> `ssl: { rejectUnauthorized: true, ca: readFileSync(process.env.RDS_CA_BUNDLE_PATH!, 'utf8') }`,
> or set `NODE_EXTRA_CA_CERTS=/app/certs/rds-global-bundle.pem` process-wide in a container.
>
> Appending `?sslmode=require` to `DATABASE_URL` is **not** a substitute: `require` only
> asks for encryption, it does not verify the server's identity.

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
- **Kysely**: Write manual `up`/`down` migration files in `src/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant constructor from `nestjs-kysely-iam.md` — no query code changes needed.
- **Auth integration** — if `templatecentral:add` (auth) ran first, `nestjs-kysely-auth.md` replaces its 501 stubs; it is loaded alongside this guide, not from it.

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
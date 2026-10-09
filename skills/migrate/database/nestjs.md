<!-- ref: migrate/database/nestjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## NestJS Database Migration

**Read `drizzle-to-kysely.md` first** — shared steps (1, 5 types, 8 migration body, 9 translation table, 10 env block, After Writing Code) live there.

```bash
cat "<skill-dir>/database/drizzle-to-kysely.md"
```

---

### Step 2 — Update `package.json` scripts

Remove `db:generate`, `db:migrate`, `db:push`, `db:studio`. Add:

```json
{
  "scripts": {
    "migrate": "tsx src/database/migrate.ts"
  }
}
```

### Step 3 — Delete Drizzle files

> **Gate — these are user files.** Create a migration branch and get explicit user confirmation before running the deletions below; never delete user code without it.

```bash
git checkout -b migrate/drizzle-to-kysely   # then confirm with the user before the rm commands
rm src/database/drizzle.service.ts
rm src/database/schema.ts
rm drizzle.config.ts
rm -rf drizzle/
```

### Step 4 — Create `src/database/kysely.service.ts` (IAM variant)

> **Canonical source**: the `KyselyService` block below and the `serviceConfig` block in
> Step 10 are duplicated verbatim from `add/database/typescript/nestjs-kysely-iam.md`
> (the IAM Auth Variant add-on leaf) — treat that file as canonical. `scripts/lint-skills.sh`
> fails the build if the two copies drift, so re-copy rather than hand-editing here.

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
into the Docker image; `RDS_CA_BUNDLE_PATH` is set in Step 10. In a container, `NODE_EXTRA_CA_CERTS=/app/certs/rds-global-bundle.pem`
is an equivalent process-wide alternative to the explicit `ca` option below.

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

### Step 5 — Create `src/database/types.ts`

Use the shared types template from `drizzle-to-kysely.md` Step 5.

### Step 6 — Update `src/database/database.module.ts`

Replace `DrizzleService` with `KyselyService`:

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

### Step 7 — Create `src/database/migrate.ts`

```typescript
import path from 'node:path';
import { promises as fs, readFileSync } from 'node:fs';
import { FileMigrationProvider, Migrator, Kysely, PostgresDialect } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

async function migrate() {
  const signer = new Signer({
    hostname: serviceConfig.DATABASE_HOST,
    port: serviceConfig.DATABASE_PORT,
    username: serviceConfig.DATABASE_USER,
  });

  const db = new Kysely<Database>({
    dialect: new PostgresDialect({
      pool: new Pool({
        host: serviceConfig.DATABASE_HOST,
        port: serviceConfig.DATABASE_PORT,
        user: serviceConfig.DATABASE_USER,
        database: serviceConfig.DATABASE_NAME,
        password: () => signer.getAuthToken(),
        ssl: {
          rejectUnauthorized: true,
          ca: readFileSync(serviceConfig.RDS_CA_BUNDLE_PATH, 'utf8'),
        },
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
    await db.destroy();
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

### Step 8 — Write first Kysely migration

Create `src/database/migrations/001_initial.ts` with the `up`/`down` pair from `drizzle-to-kysely.md` Step 8.

### Step 9 — Update query code in feature services

Use the translation table from `drizzle-to-kysely.md` Step 9.

Also update constructor injection: replace `private readonly drizzle: DrizzleService` → `private readonly db: KyselyService`.

### Step 10 — Update `src/config/env.config.ts`

Replace `DATABASE_URL` with IAM fields, in both `envSchema` and `serviceConfig`:

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

Env files: use the block and the ask-the-user rule from `drizzle-to-kysely.md` Step 10.

### Step 11 — Validate

See `drizzle-to-kysely.md` Step 11 (NestJS runs `pnpm build && pnpm test`). Then follow After Writing Code.

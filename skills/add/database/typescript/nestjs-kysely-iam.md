<!-- ref: add/database/typescript/nestjs-kysely-iam.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Kysely, compliance = AWS IAM (PostgreSQL only). Loaded alongside nestjs-kysely.md — overrides its B2 service, B6 migration-runner pool, and B7 env. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Kysely — IAM Auth Variant

> **Add-on to `nestjs-kysely.md`** (the router loads both). Work through that guide's B1–B10, but use the `KyselyService` below instead of its standard B2 service and the IAM env fields below instead of its B7 `DATABASE_URL`; then run its **After Writing Code** steps.

If the user requires AWS IAM authentication, install the additional package:

```bash
pnpm add @aws-sdk/rds-signer
```

**Download the AWS RDS CA bundle first** — follow the TLS note in `nestjs-kysely.md` (curl the
bundle, set `RDS_CA_BUNDLE_PATH`). IAM always runs against RDS, so the bundle is mandatory here.

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

> **Tests:** in B9's `test.env`, replace the `DATABASE_URL` placeholder with `DATABASE_HOST: 'localhost'`, `DATABASE_USER: 'test'`, `DATABASE_NAME: 'test'` — the pool still connects lazily.

> IAM auth does not use a password — `@aws-sdk/rds-signer` generates a short-lived token automatically from the instance's IAM role.

> **Apply the same pool config to the migration runner.** `src/database/migrate.ts` (B6) builds
> its own `Pool` from `serviceConfig.DATABASE_URL`, which no longer exists under IAM — give it the
> same `Signer` + `ssl: { rejectUnauthorized: true, ca: readFileSync(...) }` options as the service
> above, or `pnpm migrate` fails to connect while the app itself works.

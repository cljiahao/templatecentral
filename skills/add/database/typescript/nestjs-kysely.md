<!-- ref: add/database/typescript/nestjs-kysely.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Kysely (SQL, supports standard + AWS IAM auth). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Kysely (SQL)

Kysely is a type-safe SQL query builder with full SQL control and minimal overhead. It defaults to standard password authentication. AWS IAM auth and auth-stub completion live in sibling add-ons (`nestjs-kysely-iam.md`, `nestjs-kysely-auth.md`) that the router loads alongside this guide only when needed.

#### B1. Install Dependencies

`tsx` pulls in `esbuild`, whose install script pnpm 12 blocks (`ERR_PNPM_IGNORED_BUILDS`). Its platform binary ships as an optional dependency, so the script is not needed — add under the existing `allowBuilds:` in `pnpm-workspace.yaml`:

```yaml
  esbuild: false
```

```bash
pnpm add kysely pg
pnpm add -D @types/pg tsx
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

Run `TC_PART=leaf TC_LEAF=add/database/typescript/nestjs-kysely bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/typescript/nestjs-kysely/template/` (listed in `<skill-dir>/database/typescript/nestjs-kysely/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

> **Complete B7 (Configure Environment) before this step** — `serviceConfig.DATABASE_URL` must be defined before creating the service.

**`src/database/kysely.service.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nestjs-kysely/template/src/database/kysely.service.ts` by the copy step; do not re-type it.

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

Copied verbatim from `<skill-dir>/database/typescript/nestjs-kysely/template/src/database/types.ts` by the copy step; do not re-type it.

> **Tip**: After the database exists, `pnpm dlx kysely-codegen` generates these types from the live schema. Run it ad hoc rather than as a devDependency — its `micromatch → braces` chain carries a High advisory with no fixed release, which fails `pnpm audit --audit-level=high`.

#### B4. Create DatabaseModule

**`src/database/database.module.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nestjs-kysely/template/src/database/database.module.ts` by the copy step; do not re-type it.

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

Copied verbatim from `<skill-dir>/database/typescript/nestjs-kysely/template/src/database/migrations/001_initial.ts` by the copy step; do not re-type it.

Create a migration runner at **`src/database/migrate.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nestjs-kysely/template/src/database/migrate.ts` by the copy step; do not re-type it.

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

#### B9. Keep Tests Runnable Without a Database

`env.config.ts` now throws at import without `DATABASE_URL`, and Vitest does not load `.env`. Add it to the `test.env` object in **both** `vitest.config.ts` and `vitest.config.e2e.ts` (create the object if `add (auth)` has not):

```typescript
    // pg connects lazily, so this placeholder is never dialled unless a test queries.
    env: { DATABASE_URL: 'postgresql://localhost:5432/test' },
```

`KyselyService.onModuleInit` probes the database, so every e2e suite that boots `AppModule` without one (`test/app.e2e-spec.ts`, `test/auth.e2e-spec.ts`, …) overrides it:

```typescript
import { KyselyService } from '../src/database/kysely.service';

    const moduleFixture = await Test.createTestingModule({ imports: [AppModule] })
      // No database in this suite: skip KyselyService's connection probe.
      .overrideProvider(KyselyService)
      .useValue({})
      .compile();
```

Suites that exercise real queries run against a disposable Postgres (CI service container) with `DATABASE_URL` set in the job env, which `test.env` does not override.

#### B10. Validate

```bash
pnpm check && pnpm build && pnpm test && pnpm test:e2e
```

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place `KyselyService` and `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Kysely**: Write manual `up`/`down` migration files in `src/database/migrations/`, named `NNN_<description>.ts` with the next unused number — Kysely runs migrations in name order and, by default, fails when a new file sorts before one already executed. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant constructor from `nestjs-kysely-iam.md` — no query code changes needed.
- **Auth integration** — if `templatecentral:add` (auth) ran first, `nestjs-kysely-auth.md` replaces its 501 stubs; it is loaded alongside this guide, not from it.

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
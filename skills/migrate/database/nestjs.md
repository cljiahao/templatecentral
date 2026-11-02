<!-- ref: migrate/database/nestjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## NestJS Database Migration

**Read `drizzle-to-kysely.md` first** — shared steps (1, 5 types, 8 migration body, 9 translation table, 10 env block, After Writing Code) live there.

```bash
cat "<skill-dir>/database/drizzle-to-kysely.md"
```

**Before Step 1**, create a migration branch so every change below (packages, scripts, deletions) is reviewable and revertible as one unit:

`git checkout -b migrate/drizzle-to-kysely`

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

> **Gate — these are user files.** Get explicit user confirmation before running the deletions below; never delete user code without it. The migration branch already exists (created before Step 1), so skip the first line if you are on it.

```bash
git checkout -b migrate/drizzle-to-kysely   # then confirm with the user before the rm commands
rm src/database/drizzle.service.ts
rm src/database/schema.ts
rm drizzle.config.ts
rm -rf drizzle/
```

### Step 4 — Create `src/database/kysely.service.ts` (IAM variant)

> **Canonical source**: the copied `src/database/kysely.service.ts` and the `serviceConfig` block in
> Step 10 match `add/database/typescript/nestjs-kysely-iam.md` (canonical).
> The lint fails if they drift: re-copy, do not hand-edit.

**Download the AWS RDS CA bundle first.** The Amazon RDS root CA is not in Node's default trust
store, so without the bundle TLS fails with `SELF_SIGNED_CERT_IN_CHAIN`. Never "fix" it with
`rejectUnauthorized: false`: that silently downgrades to unauthenticated TLS.

```bash
mkdir -p certs
curl -fsSL -o certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Run `TC_PART=leaf TC_LEAF=migrate/database/nestjs bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/nestjs/template/` (listed in `<skill-dir>/database/nestjs/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

Commit `certs/rds-global-bundle.pem` (it is a public certificate, not a secret) or bake it
into the Docker image; `RDS_CA_BUNDLE_PATH` is set in Step 10. In a container, `NODE_EXTRA_CA_CERTS=/app/certs/rds-global-bundle.pem`
is an equivalent process-wide alternative to the explicit `ca` option in the copied `kysely.service.ts`.

Copied verbatim from `<skill-dir>/database/nestjs/template/src/database/kysely.service.ts` by the copy step; do not re-type it.

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

Copied verbatim from `<skill-dir>/database/nestjs/template/src/database/migrate.ts` by the copy step; do not re-type it.

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

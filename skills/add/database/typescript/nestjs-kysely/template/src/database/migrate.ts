// Runs outside main.ts, so it must load .env itself before env.config validates.
import 'dotenv/config';
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { Kysely, PostgresDialect } from 'kysely';
// Migration classes live under the kysely/migration subpath.
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

// Without the catch a rejected promise leaves exit code 0 and CI passes a failed migration.
migrate().catch((e) => {
  console.error(e);
  process.exit(1);
});

// Runs outside main.ts, so it must load .env itself before env.config validates.
import 'dotenv/config';
import path from 'node:path';
import { promises as fs, readFileSync } from 'node:fs';
import { Kysely, PostgresDialect } from 'kysely';
// kysely ≥0.29 types the root-export Migrator/FileMigrationProvider as errors pointing here.
import { FileMigrationProvider, Migrator } from 'kysely/migration';
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

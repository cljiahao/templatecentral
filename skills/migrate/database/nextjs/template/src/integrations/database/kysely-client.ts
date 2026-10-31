import { readFileSync } from 'node:fs';
import { Signer } from '@aws-sdk/rds-signer';
import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import type { Database } from './types';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

function createDb(): Kysely<Database> {
  const host = requireEnv('DATABASE_HOST');
  const port = Number(process.env.DATABASE_PORT ?? '5432');
  const user = requireEnv('DATABASE_USER');
  const signer = new Signer({ hostname: host, port, username: user });

  const pool = new Pool({
    host,
    port,
    user,
    database: requireEnv('DATABASE_NAME'),
    password: () => signer.getAuthToken(),
    ssl: { rejectUnauthorized: true, ca: readFileSync(requireEnv('RDS_CA_BUNDLE_PATH'), 'utf8') },
    max: 10,
  });

  return new Kysely<Database>({ dialect: new PostgresDialect({ pool }) });
}

// Reuse one pool across dev hot reloads instead of leaking a new one per reload
const globalForKysely = globalThis as unknown as { db?: Kysely<Database> };

export const db = globalForKysely.db ?? createDb();

if (process.env.NODE_ENV !== 'production') globalForKysely.db = db;

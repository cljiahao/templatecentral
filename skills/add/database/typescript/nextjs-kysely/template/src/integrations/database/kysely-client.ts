import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import type { Database } from './types';

function createPool() {
  return new Pool({
    connectionString: process.env.DATABASE_URL,
    // TLS required for non-local databases; rejectUnauthorized: false would accept a MITM proxy.
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined,
    max: 10,
  });
}

const globalForKysely = globalThis as unknown as { db?: Kysely<Database> };

export const db =
  globalForKysely.db ?? new Kysely<Database>({ dialect: new PostgresDialect({ pool: createPool() }) });

if (process.env.NODE_ENV !== 'production') globalForKysely.db = db;

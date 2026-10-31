import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import type { Database } from './types';

function createPool() {
  return new Pool({
    connectionString: process.env.DATABASE_URL,
    // TLS is required for any non-local database. Verify the server certificate —
    // `rejectUnauthorized: false` accepts a MITM proxy silently.
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined,
    max: 10,
  });
}

const globalForKysely = globalThis as unknown as { db?: Kysely<Database> };

export const db =
  globalForKysely.db ?? new Kysely<Database>({ dialect: new PostgresDialect({ pool: createPool() }) });

if (process.env.NODE_ENV !== 'production') globalForKysely.db = db;

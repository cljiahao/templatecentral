import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

// v1's drizzle() generic is TRelations, not the schema; tables are passed per query.
const globalForDb = globalThis as unknown as { db?: ReturnType<typeof drizzle> };

export const db =
  globalForDb.db ??
  drizzle({
    client: postgres(process.env.DATABASE_URL!, {
      // postgres.js defaults to plaintext. Local Docker Postgres serves no TLS, so only
      // `next dev` skips it; 'verify-full' checks the certificate chain and hostname.
      ssl: process.env.NODE_ENV === 'production' ? 'verify-full' : false,
    }),
  });

if (process.env.NODE_ENV !== 'production') globalForDb.db = db;

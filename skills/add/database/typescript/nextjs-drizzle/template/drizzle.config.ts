import { existsSync } from 'node:fs';
import { defineConfig } from 'drizzle-kit';

// drizzle-kit does not read Next.js's .env.local. Load it locally when present; CI and
// deploy jobs inject DATABASE_URL directly and have no such file (loadEnvFile would throw).
if (existsSync('.env.local')) process.loadEnvFile('.env.local');

export default defineConfig({
  schema: './src/integrations/database/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});

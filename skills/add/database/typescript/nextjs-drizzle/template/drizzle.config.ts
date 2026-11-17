import { existsSync } from 'node:fs';
import { defineConfig } from 'drizzle-kit';

// drizzle-kit does not read .env.local; CI injects DATABASE_URL, so load it only when present.
if (existsSync('.env.local')) process.loadEnvFile('.env.local');

export default defineConfig({
  schema: './src/integrations/database/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});

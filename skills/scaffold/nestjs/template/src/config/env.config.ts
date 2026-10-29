import { z } from 'zod';

const envSchema = z.object({
  PROJECT_NAME: z.string().min(1).default('My Project'),
  PROJECT_DESCRIPTION: z
    .string()
    .min(1)
    .default('API built with [NestJS](https://nestjs.com/) + Fastify'),
  PROJECT_VERSION: z.string().min(1).default('0.1.0'),
  ENVIRONMENT: z.enum(['dev', 'uat', 'prod']).default('dev'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  CLIENT_URL: z.string().min(1).default('http://localhost:3000'),
  // Reverse proxy trust: comma-separated IPs/CIDRs, or "*" — see main.ts's resolveTrustProxy().
  TRUST_PROXY: z.string().optional(),
  // Injected by appCentral at runtime: the only origin allowed to frame this app. Not
  // validated here — an invalid value must deny framing, not fail boot (see security.setup.ts).
  APPCENTRAL_PORTAL_ORIGIN: z.string().optional(),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal', 'silent']).default('info'),
});

// An empty value in `.env` means "not set" — drop it so the schema default applies.
const rawEnv = Object.fromEntries(Object.entries(process.env).filter(([, value]) => value !== ''));

const parsed = envSchema.safeParse(rawEnv);

// Fail at import time. A `!` assertion is erased at compile time and would surface a
// missing variable as an obscure runtime failure on the first request instead.
if (!parsed.success) {
  throw new Error(`Invalid environment configuration:\n${z.prettifyError(parsed.error)}`);
}

const env = parsed.data;

export const appConfig = {
  PROJECT_NAME: env.PROJECT_NAME,
  PROJECT_DESCRIPTION: env.PROJECT_DESCRIPTION,
  PROJECT_VERSION: env.PROJECT_VERSION,
  ENVIRONMENT: env.ENVIRONMENT,
  PORT: env.PORT,
  TRUST_PROXY: env.TRUST_PROXY,
  APPCENTRAL_PORTAL_ORIGIN: env.APPCENTRAL_PORTAL_ORIGIN,
  LOG_LEVEL: env.LOG_LEVEL,
};

export const serviceConfig = {
  CLIENT_URL: env.CLIENT_URL.split(',').map((url) => url.trim()),
};

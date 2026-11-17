import pino from 'pino';

// pino has no default redaction; list credential paths and never build them from user input.
const redact = [
  'password',
  '*.password',
  'token',
  '*.token',
  'accessToken',
  'refreshToken',
  'authorization',
  'req.headers.authorization',
  'req.headers.cookie',
  'res.headers["set-cookie"]',
];

function createLogger() {
  return pino({
    level: process.env.LOG_LEVEL ?? 'info',
    redact,
    ...(process.env.NODE_ENV !== 'production' && {
      transport: {
        target: 'pino-pretty',
        options: { colorize: true, singleLine: true },
      },
    }),
  });
}

// Cached on globalThis in dev: HMR re-imports would spawn a pino-pretty transport per reload.
const globalForLogger = globalThis as unknown as {
  __logger?: ReturnType<typeof createLogger>;
};

export const logger = globalForLogger.__logger ?? createLogger();

if (process.env.NODE_ENV !== 'production') globalForLogger.__logger = logger;

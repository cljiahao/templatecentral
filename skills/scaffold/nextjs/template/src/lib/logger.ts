import pino from 'pino';

// pino ships NO redaction by default — logging a raw `req`/`res` or an object that
// carries credentials would otherwise leak secrets. Paths are case-sensitive; wildcards
// (`*.token`) cost more but catch nested fields. Never build these paths from user input.
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

// Cache the logger on globalThis in dev. Next.js HMR re-imports this module on every hot
// reload; without the cache each reload spawns a fresh pino-pretty transport (a thread-stream
// worker), and the accumulating listeners trip Node's MaxListenersExceededWarning. This mirrors
// the canonical Next.js PrismaClient singleton pattern. In production a single instance is used.
const globalForLogger = globalThis as unknown as {
  __logger?: ReturnType<typeof createLogger>;
};

export const logger = globalForLogger.__logger ?? createLogger();

if (process.env.NODE_ENV !== 'production') globalForLogger.__logger = logger;

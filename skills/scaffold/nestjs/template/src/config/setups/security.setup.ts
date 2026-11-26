import fastifyHelmet from '@fastify/helmet';
import type { INestApplication } from '@nestjs/common';
import type { FastifyInstance } from 'fastify';
import { appConfig, serviceConfig } from '../env.config';

// One https origin only; anything else denies, so the value cannot inject CSP directives.
const PORTAL_ORIGIN_RE = /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+$/;

/** The validated EMBED_PARENT_ORIGIN, or null when unset or invalid. */
export function portalFrameAncestor(origin: string | undefined): string | null {
  return origin && PORTAL_ORIGIN_RE.test(origin) ? origin : null;
}

export async function setupSecurity(app: INestApplication): Promise<void> {
  const fastify = app.getHttpAdapter().getInstance() as FastifyInstance;

  // Frame protection is skipped in dev so Swagger UI renders in IDE preview panes.
  const isDev = appConfig.ENVIRONMENT === 'dev';
  // Only the portal origin may frame the app.
  const portal = portalFrameAncestor(appConfig.EMBED_PARENT_ORIGIN);

  await fastify.register(fastifyHelmet, {
    crossOriginResourcePolicy: { policy: 'cross-origin' },
    contentSecurityPolicy: {
      directives: {
        'default-src': ["'self'"],
        'script-src': ["'self'"],
        'style-src': ["'self'", "'unsafe-inline'"],
        'img-src': ["'self'", 'data:', 'https:'],
        'object-src': ["'none'"],
        'base-uri': ["'none'"],
        // null omits the directive; an empty array does not.
        'frame-ancestors': isDev ? null : [portal ?? "'none'"],
      },
    },
    strictTransportSecurity: { maxAge: 31536000, includeSubDomains: true },
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    // X-Frame-Options is sent only when framing is denied; the action must be lowercase.
    frameguard: isDev || portal ? false : { action: 'deny' },
  });

  fastify.addHook('onSend', async (_request, reply, payload) => {
    // Per-user data must not reach shared caches.
    void reply.header('Cache-Control', 'no-cache, no-store, must-revalidate, private');
    void reply.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    return payload;
  });
}

export function setupCors(app: INestApplication): void {
  app.enableCors({
    origin: serviceConfig.CLIENT_URL,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization'],
  });
}

import fastifyHelmet from '@fastify/helmet';
import type { INestApplication } from '@nestjs/common';
import type { FastifyInstance } from 'fastify';
import { appConfig, serviceConfig } from '../env.config';

// Exactly one https origin: lowercase host labels, no path, port, wildcard, quotes,
// whitespace or semicolons. Anything else falls back to deny, so the value can never
// inject extra CSP directives or headers.
const PORTAL_ORIGIN_RE = /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+$/;

/** The validated APPCENTRAL_PORTAL_ORIGIN, or null when unset or invalid. */
export function portalFrameAncestor(origin: string | undefined): string | null {
  return origin && PORTAL_ORIGIN_RE.test(origin) ? origin : null;
}

export async function setupSecurity(app: INestApplication): Promise<void> {
  const fastify = app.getHttpAdapter().getInstance() as FastifyInstance;

  // Anti-clickjacking (frame-ancestors, X-Frame-Options) is skipped in dev — Swagger UI at
  // /docs is otherwise blocked from rendering in IDE-embedded preview panes (most render via
  // <iframe>, and browsers enforce these headers even for localhost). Full protection still
  // applies in every deployed environment (prod, uat).
  const isDev = appConfig.ENVIRONMENT === 'dev';
  // Only the appCentral portal (APPCENTRAL_PORTAL_ORIGIN, injected at runtime) may frame
  // the app; unset or invalid denies all framing.
  const portal = portalFrameAncestor(appConfig.APPCENTRAL_PORTAL_ORIGIN);

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
        // null omits the directive from the emitted header — an empty array does not:
        // Helmet's own default for an unset frame-ancestors is 'self', which would still
        // block a cross-origin IDE-preview iframe.
        'frame-ancestors': isDev ? null : [portal ?? "'none'"],
      },
    },
    strictTransportSecurity: { maxAge: 31536000, includeSubDomains: true },
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    // frameguard sets X-Frame-Options (xFrameOptions is an equivalent alias). action must be
    // lowercase — 'deny' | 'sameorigin', not 'DENY' — per @fastify/helmet's actual type.
    // X-Frame-Options cannot express a single allowed origin; frame-ancestors supersedes it,
    // so it is sent only when framing is denied outright.
    frameguard: isDev || portal ? false : { action: 'deny' },
  });

  fastify.addHook('onSend', async (_request, reply, payload) => {
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

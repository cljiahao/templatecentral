// One https origin only; anything else denies, so the value cannot inject CSP directives.
const PORTAL_ORIGIN_RE = /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+$/;

// Single source of the app's CSP: add directives here, not in next.config.ts headers().
const CSP_BASE = "base-uri 'self'; object-src 'none'; form-action 'self'";

// Responses rewritten to the backend keep the backend's own security headers.
const BACKEND_PROXY_PATH = '/api/external';

function isBackendProxyPath(pathname: string): boolean {
  return pathname === BACKEND_PROXY_PATH || pathname.startsWith(`${BACKEND_PROXY_PATH}/`);
}

function portalOrigin(): string | null {
  const origin = process.env.EMBED_PARENT_ORIGIN;
  return origin && PORTAL_ORIGIN_RE.test(origin) ? origin : null;
}

// Frame protection is omitted in dev for IDE previews; frame-ancestors supersedes X-Frame-Options, so that is not sent.
export function applyFrameProtection<T extends Response>(pathname: string, res: T): T {
  if (isBackendProxyPath(pathname)) return res;
  if (process.env.NODE_ENV === 'development') {
    res.headers.set('Content-Security-Policy', CSP_BASE);
    return res;
  }
  const origin = portalOrigin();
  if (origin) {
    res.headers.set('Content-Security-Policy', `frame-ancestors ${origin}; ${CSP_BASE}`);
    res.headers.delete('X-Frame-Options');
  } else {
    res.headers.set('Content-Security-Policy', `frame-ancestors 'none'; ${CSP_BASE}`);
    res.headers.set('X-Frame-Options', 'DENY');
  }
  return res;
}

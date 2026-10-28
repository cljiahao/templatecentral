// Exactly one https origin: lowercase host labels, no path, port, wildcard, quotes,
// whitespace or semicolons. Anything else falls back to deny, so the value can never
// inject extra CSP directives or headers.
const PORTAL_ORIGIN_RE = /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+$/;

// CSP baseline — tighten after auth/analytics are wired. The single source of the app's CSP:
// add new directives here, not in next.config.ts headers() (this header replaces any CSP set
// earlier on the response).
const CSP_BASE = "base-uri 'self'; object-src 'none'; form-action 'self'";

// Responses rewritten to the backend (standards full-stack-pairing: /api/external/* →
// BACKEND_URL) keep the backend's own, stricter security headers untouched.
const BACKEND_PROXY_PATH = '/api/external';

function isBackendProxyPath(pathname: string): boolean {
  return pathname === BACKEND_PROXY_PATH || pathname.startsWith(`${BACKEND_PROXY_PATH}/`);
}

function portalOrigin(): string | null {
  const origin = process.env.APPCENTRAL_PORTAL_ORIGIN;
  return origin && PORTAL_ORIGIN_RE.test(origin) ? origin : null;
}

export function applyFrameProtection<T extends Response>(pathname: string, res: T): T {
  if (isBackendProxyPath(pathname)) return res;
  // Anti-clickjacking is omitted in dev: browsers enforce it even for localhost, which
  // blocks IDE-embedded preview panes (most render via <iframe>). Every deployed
  // environment gets it.
  if (process.env.NODE_ENV === 'development') {
    res.headers.set('Content-Security-Policy', CSP_BASE);
    return res;
  }
  const origin = portalOrigin();
  if (origin) {
    // frame-ancestors supersedes X-Frame-Options, which cannot express a single
    // allowed origin, so X-Frame-Options is not sent.
    res.headers.set('Content-Security-Policy', `frame-ancestors ${origin}; ${CSP_BASE}`);
    res.headers.delete('X-Frame-Options');
  } else {
    res.headers.set('Content-Security-Policy', `frame-ancestors 'none'; ${CSP_BASE}`);
    res.headers.set('X-Frame-Options', 'DENY');
  }
  return res;
}

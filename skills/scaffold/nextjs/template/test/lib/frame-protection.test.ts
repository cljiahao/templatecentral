import { afterEach, describe, expect, it, vi } from 'vitest';

import { applyFrameProtection } from '@/lib/security/frame-protection';

const CSP_BASE = "base-uri 'self'; object-src 'none'; form-action 'self'";

function framed(pathname = '/'): Response {
  return applyFrameProtection(pathname, new Response(null));
}

describe('applyFrameProtection', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('denies all framing when APPCENTRAL_PORTAL_ORIGIN is unset', () => {
    const res = framed();
    expect(res.headers.get('X-Frame-Options')).toBe('DENY');
    expect(res.headers.get('Content-Security-Policy')).toBe(`frame-ancestors 'none'; ${CSP_BASE}`);
  });

  it('allows only the portal origin and drops X-Frame-Options', () => {
    vi.stubEnv('APPCENTRAL_PORTAL_ORIGIN', 'https://appcentral-uat.cpfnet.gov.sg');
    const res = framed();
    expect(res.headers.get('X-Frame-Options')).toBeNull();
    expect(res.headers.get('Content-Security-Policy')).toBe(
      `frame-ancestors https://appcentral-uat.cpfnet.gov.sg; ${CSP_BASE}`,
    );
  });

  it.each([
    'http://appcentral.example.gov.sg',
    'https://*.example.gov.sg',
    'https://example.gov.sg:8443',
    'https://example.gov.sg/path',
    "https://example.gov.sg; script-src 'unsafe-inline'",
    'https://example.gov.sg\nX-Injected: 1',
    'https://localhost',
    '*',
  ])('falls back to deny for invalid origin %s', (origin) => {
    vi.stubEnv('APPCENTRAL_PORTAL_ORIGIN', origin);
    const res = framed();
    expect(res.headers.get('X-Frame-Options')).toBe('DENY');
    expect(res.headers.get('Content-Security-Policy')).toBe(`frame-ancestors 'none'; ${CSP_BASE}`);
  });

  it.each(['/api/external', '/api/external/items'])(
    'leaves backend-proxied responses (%s) untouched',
    (pathname) => {
      vi.stubEnv('APPCENTRAL_PORTAL_ORIGIN', 'https://appcentral-uat.cpfnet.gov.sg');
      const backend = new Response(null, {
        headers: { 'Content-Security-Policy': "default-src 'none'", 'X-Frame-Options': 'DENY' },
      });
      const res = applyFrameProtection(pathname, backend);
      expect(res.headers.get('Content-Security-Policy')).toBe("default-src 'none'");
      expect(res.headers.get('X-Frame-Options')).toBe('DENY');
    },
  );

  it('still protects paths that only share the prefix', () => {
    expect(framed('/api/externalx').headers.get('X-Frame-Options')).toBe('DENY');
  });
});

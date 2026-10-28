import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Standalone only for the Docker image (builder sets NEXT_OUTPUT); `next start` rejects it locally.
  output: process.env.NEXT_OUTPUT === 'standalone' ? 'standalone' : undefined,
  reactStrictMode: true,
  poweredByHeader: false,

  // next/image refuses external hosts until they are allowlisted in `images.remotePatterns`.

  async headers() {
    // Content-Security-Policy and X-Frame-Options are NOT set here. headers() is resolved at
    // build time, but the allowed framing origin (APPCENTRAL_PORTAL_ORIGIN) is injected at
    // runtime, so src/proxy.ts sets both per request via src/lib/security/frame-protection.ts.
    // That file is the only place the CSP is defined: add new CSP directives there, never here.
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
          { key: 'X-XSS-Protection', value: '0' },
          // HSTS — browsers ignore HSTS received over HTTP, so this is only effective over HTTPS.
          { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
        ],
      },
    ];
  },
};

export default nextConfig;

import type { NextConfig } from 'next';

// CSP and X-Frame-Options are set per request in src/proxy.ts, because the framing origin is only known at runtime.
// HSTS — browsers ignore HSTS received over HTTP, so this is only effective over HTTPS.
const nextConfig: NextConfig = {
  // Standalone only for the Docker image; `next start` rejects it locally.
  output: process.env.NEXT_OUTPUT === 'standalone' ? 'standalone' : undefined,
  reactStrictMode: true,
  poweredByHeader: false,


  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
          { key: 'X-XSS-Protection', value: '0' },
          { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
        ],
      },
    ];
  },
};

export default nextConfig;

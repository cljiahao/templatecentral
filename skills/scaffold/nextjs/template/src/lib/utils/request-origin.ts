import { type NextRequest } from 'next/server';

// TRUST_PROXY is the number of trusted proxy hops in front of the app (1 = ALB → App,
// 2 = ALB → Traefik → App); unset or empty means X-Forwarded-* headers are ignored.
// Callers MUST validate the resolved host against an ALLOWED_HOSTS set before emitting
// it in any URL (password reset links, OAuth callbacks) — this function alone does not
// prevent Host header injection.
export function getAppOrigin(request: NextRequest): string {
  const trustProxy = process.env.TRUST_PROXY;
  const proto = (trustProxy
    ? request.headers.get('x-forwarded-proto')?.split(',')[0].trim()
    : undefined) ?? request.nextUrl.protocol.replace(/:$/, '');
  const host = (trustProxy
    ? (request.headers.get('x-forwarded-host') ?? request.headers.get('host'))
    : undefined) ?? request.nextUrl.host;
  return `${proto}://${host}`;
}

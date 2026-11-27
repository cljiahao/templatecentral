import { type NextRequest } from 'next/server';

// Unset TRUST_PROXY ignores X-Forwarded-*; callers must check the host against ALLOWED_HOSTS to stop Host injection.
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

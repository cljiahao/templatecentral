import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

import { logger } from '@/lib/logger';

// Generic over the route context so typed dynamic-segment params survive the wrap:
//   export const GET = withLogging(async (req) => …)                                    // static
//   export const GET = withLogging<RouteContext<{ id: string }>>(async (req, { params }) => …)  // dynamic
export type RouteContext<P = Record<string, string>> = { params: Promise<P> };

// Plain `Response` (not NextResponse) so library handlers such as better-auth's wrap directly.
type RouteHandler<C> = (req: NextRequest, ctx: C) => Promise<Response>;

// The returned handler takes the context via a variadic tuple ([ctx] | []) so static routes
// (and unit tests) can call it with just the request, while dynamic routes still receive
// their typed params. Next.js passes the context for dynamic segments at runtime.
export function withLogging<C = unknown>(
  handler: RouteHandler<C>
): (req: NextRequest, ...rest: [ctx: C] | []) => Promise<Response> {
  return async (req, ...rest) => {
    const start = Date.now();
    const { method } = req;
    const path = new URL(req.url).pathname;
    const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID();

    try {
      const res = await handler(req, ...(rest as [ctx: C]));
      logger.info({ requestId, method, path, status: res.status, duration_ms: Date.now() - start });
      return res;
    } catch (err) {
      logger.error({
        requestId,
        method,
        path,
        error: err instanceof Error ? err.message : String(err),
      });
      return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
    }
  };
}

import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

import { logger } from '@/lib/logger';

export type RouteContext<P = Record<string, string>> = { params: Promise<P> };

type RouteHandler<C> = (req: NextRequest, ctx: C) => Promise<Response>;

// The variadic context tuple lets static routes and unit tests call it with just the request.
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

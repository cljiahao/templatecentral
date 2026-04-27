import { type NextRequest, NextResponse } from 'next/server';

import { logger } from '@/lib/logger';

export function withLogging<T extends unknown[]>(
  handler: (req: NextRequest, ...args: T) => Promise<NextResponse> | NextResponse,
): (req: NextRequest, ...args: T) => Promise<NextResponse> {
  return async (req: NextRequest, ...args: T): Promise<NextResponse> => {
    const start = Date.now();
    const { method } = req;
    const path = req.nextUrl?.pathname ?? new URL(req.url).pathname;

    try {
      const response = await handler(req, ...args);
      logger.info({
        method,
        path,
        status_code: response.status,
        duration_ms: Date.now() - start,
      });
      return response;
    } catch (error) {
      logger.error({
        method,
        path,
        duration_ms: Date.now() - start,
        err: error,
      });
      throw error;
    }
  };
}

import { type NextRequest, NextResponse } from 'next/server';

import { withLogging } from '@/lib/utils/with-logging';

// Every route handler is wrapped in withLogging — the base scaffold models the pattern
// its own health checks depend on, and the lint gate (see AGENTS.md) enforces it.
export const GET = withLogging(async (_req: NextRequest): Promise<NextResponse> => {
  return NextResponse.json(
    { status: 'ok', timestamp: new Date().toISOString() },
    { status: 200 },
  );
});

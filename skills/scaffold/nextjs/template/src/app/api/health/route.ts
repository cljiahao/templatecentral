import { type NextRequest, NextResponse } from 'next/server';

import { withLogging } from '@/lib/utils/with-logging';

// Wrapped in withLogging, as the lint gate requires.
export const GET = withLogging(async (_req: NextRequest): Promise<NextResponse> => {
  return NextResponse.json(
    { status: 'ok', timestamp: new Date().toISOString() },
    { status: 200 },
  );
});

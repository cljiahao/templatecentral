import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

import { applyFrameProtection } from '@/lib/security/frame-protection';

export function proxy(req: NextRequest) {
  return applyFrameProtection(req.nextUrl.pathname, NextResponse.next());
}

// Build output and optimised images are not documents and are never framed, so they get no
// CSP or X-Frame-Options.
export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};

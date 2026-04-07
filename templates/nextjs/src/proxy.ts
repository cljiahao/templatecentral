import { auth } from '@/auth';
import { API_ROUTES, PAGE_ROUTES } from '@/lib/constants/routes';
import { NextResponse } from 'next/server';

const PUBLIC_PATHS = new Set<string>([PAGE_ROUTES.HOME, PAGE_ROUTES.LOGIN]);
const PUBLIC_API_PREFIXES = ['/api/auth', API_ROUTES.HEALTH];

function isApiRoute(pathname: string): boolean {
  return pathname.startsWith('/api/');
}

function isPublicRoute(pathname: string): boolean {
  return PUBLIC_PATHS.has(pathname) || PUBLIC_API_PREFIXES.some((p) => pathname.startsWith(p));
}

export const proxy = auth((req) => {
  const { pathname } = req.nextUrl;
  const isAuthenticated = !!req.auth;

  if (!isAuthenticated && !isPublicRoute(pathname)) {
    if (isApiRoute(pathname)) {
      return new Response(null, { status: 401 });
    }
    return NextResponse.redirect(new URL(PAGE_ROUTES.LOGIN, req.url));
  }

  if (isAuthenticated && pathname === PAGE_ROUTES.LOGIN) {
    return NextResponse.redirect(new URL(PAGE_ROUTES.DASHBOARD, req.url));
  }

  return NextResponse.next();
});

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|.*\\.(?:svg|png|jpg|jpeg|gif|ico|webp)$).*)',
  ],
};

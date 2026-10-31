import { ForbiddenException } from '@nestjs/common';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

import { appConfig } from '../../config/env.config';

// Secure is dropped only in dev (plain-http localhost); the __Host- prefix requires Secure,
// so the session cookie takes its hardened name everywhere else.
export const COOKIE_SECURE = appConfig.ENVIRONMENT !== 'dev';
export const SESSION_COOKIE = COOKIE_SECURE ? '__Host-session' : 'session';
// Readable by the SPA, which echoes it back in the X-CSRF-Token header (Fastify lower-cases
// incoming header names, hence the lookup key).
export const CSRF_COOKIE = 'XSRF-TOKEN';
export const CSRF_HEADER = 'x-csrf-token';
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);
// Sub-key so the CSRF HMAC never shares raw key material with JWT signing.
const CSRF_KEY = createHmac('sha256', appConfig.JWT_SECRET).update('csrf-v1').digest();

function csrfSignature(session: string, nonce: string): string {
  // Length-prefixed message (OWASP signed double-submit) binds the token to the session.
  return createHmac('sha256', CSRF_KEY)
    .update(`${session.length}!${session}!${nonce.length}!${nonce}`)
    .digest('hex');
}

function createCsrfToken(session: string): string {
  const nonce = randomBytes(32).toString('base64url');
  return `${nonce}.${csrfSignature(session, nonce)}`;
}

function verifyCsrfToken(token: string, session: string): boolean {
  const [nonce, signature = ''] = token.split('.', 2);
  if (!nonce) return false;
  const expected = Buffer.from(csrfSignature(session, nonce));
  const actual = Buffer.from(signature);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

// req.cookies exists only once @fastify/cookie is registered (setupSecurity) — suites that build
// the app without it must still get a clean 401, not a TypeError.
function readCookie(req: FastifyRequest, name: string): string | undefined {
  return (req.cookies as Partial<Record<string, string>> | undefined)?.[name];
}

/** passport-jwt extractor: the session cookie set by `setSessionCookies`. */
export function fromSessionCookie(req: FastifyRequest): string | null {
  return readCookie(req, SESSION_COOKIE) ?? null;
}

/** Cookie-authenticated unsafe requests must echo a CSRF token bound to the session. */
export function assertCsrf(req: FastifyRequest): void {
  const session = readCookie(req, SESSION_COOKIE);
  // Bearer requests are not CSRF-exposed: browsers never attach Authorization on their own.
  if (SAFE_METHODS.has(req.method) || req.headers.authorization || !session) return;
  const header = req.headers[CSRF_HEADER];
  if (
    typeof header !== 'string' ||
    header !== readCookie(req, CSRF_COOKIE) ||
    !verifyCsrfToken(header, session)
  ) {
    throw new ForbiddenException('CSRF token missing or invalid.');
  }
}

export function setSessionCookies(reply: FastifyReply, token: string): void {
  const options = {
    path: '/',
    secure: COOKIE_SECURE,
    sameSite: 'strict',
    maxAge: appConfig.JWT_EXPIRES_IN_SECONDS,
  } as const;
  void reply.setCookie(SESSION_COOKIE, token, { ...options, httpOnly: true });
  // Readable on purpose: the SPA echoes it back in the X-CSRF-Token header.
  void reply.setCookie(CSRF_COOKIE, createCsrfToken(token), { ...options, httpOnly: false });
}

export function clearSessionCookies(reply: FastifyReply): void {
  // Attributes must match, or browsers ignore the deletion of a __Host- cookie.
  const options = { path: '/', secure: COOKIE_SECURE, sameSite: 'strict' } as const;
  void reply.clearCookie(SESSION_COOKIE, { ...options, httpOnly: true });
  void reply.clearCookie(CSRF_COOKIE, options);
}

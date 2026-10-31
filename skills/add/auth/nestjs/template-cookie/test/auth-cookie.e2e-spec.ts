import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { Controller, Post, UseGuards } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Test } from '@nestjs/testing';
import { AppModule } from '../src/app.module';
import { setupCors, setupSecurity } from '../src/config';
import { COOKIE_SECURE, CSRF_COOKIE, SESSION_COOKIE } from '../src/modules/auth/auth.cookies';
import { AuthService } from '../src/modules/auth/auth.service';
import { JwtAuthGuard } from '../src/modules/auth/jwt-auth.guard';

// A guarded unsafe route, so the CSRF check is exercised independently of feature modules.
@Controller('csrf-probe')
@UseGuards(JwtAuthGuard)
class CsrfProbeController {
  @Post()
  write() {
    return { ok: true };
  }
}

type SetCookie = string | string[] | undefined;

/** name=value pairs from Set-Cookie, ready for a Cookie request header. */
function cookieHeader(setCookie: SetCookie): string {
  return [setCookie ?? []]
    .flat()
    .map((c) => c.split(';')[0])
    .join('; ');
}

function cookieValue(setCookie: SetCookie, name: string): string {
  const pair = [setCookie ?? []].flat().find((c) => c.startsWith(`${name}=`)) ?? '';
  return decodeURIComponent(pair.split(';')[0].slice(name.length + 1));
}

describe('Auth cookie mode (e2e)', () => {
  let app: NestFastifyApplication;
  let setCookie: SetCookie;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
      controllers: [CsrfProbeController],
    })
      // Add the same .overrideProvider(...) calls your auth.e2e-spec.ts carries (database guides).
      .compile();
    app = moduleFixture.createNestApplication<NestFastifyApplication>(new FastifyAdapter());
    // Registers @fastify/cookie and CORS exactly as main.ts does.
    await setupSecurity(app);
    setupCors(app);
    await app.init();
    await app.getHttpAdapter().getInstance().ready();

    // Stand-in for AuthService.login (a stub until the database guide lands): any valid token
    // works for the cookie checks.
    const accessToken = await app
      .get(JwtService)
      .signAsync({ sub: 'user-1', email: 'a@example.com' });
    vi.spyOn(app.get(AuthService), 'login').mockResolvedValue({ accessToken, tokenType: 'bearer' });
    const res = await app.inject({
      method: 'POST',
      url: '/auth/session',
      payload: { email: 'a@example.com', password: 'x'.repeat(12) },
    });
    expect(res.statusCode).toBe(204);
    expect(res.body).toBe('');
    setCookie = res.headers['set-cookie'];
  });

  afterAll(async () => {
    await app.close();
  });

  it('sets an HttpOnly, SameSite=Strict session cookie and a readable CSRF cookie', () => {
    const cookies = [setCookie ?? []].flat();
    const session = cookies.find((c) => c.startsWith(`${SESSION_COOKIE}=`)) ?? '';
    const csrf = cookies.find((c) => c.startsWith(`${CSRF_COOKIE}=`)) ?? '';
    expect(session).toMatch(/HttpOnly/);
    expect(csrf).not.toMatch(/HttpOnly/);
    for (const cookie of [session, csrf]) {
      expect(cookie).toMatch(/SameSite=Strict/);
      expect(cookie).toMatch(/Path=\//);
      expect(/Secure/.test(cookie)).toBe(COOKIE_SECURE);
    }
  });

  it('authenticates GET /auth/me from the cookie alone', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/auth/me',
      headers: { cookie: cookieHeader(setCookie) },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: 'user-1', email: 'a@example.com', roles: [] });
  });

  it('rejects a cookie-authenticated POST without a valid CSRF header', async () => {
    const cookie = cookieHeader(setCookie);
    const missing = await app.inject({ method: 'POST', url: '/csrf-probe', headers: { cookie } });
    expect(missing.statusCode).toBe(403);
    const forged = await app.inject({
      method: 'POST',
      url: '/csrf-probe',
      headers: { cookie, 'x-csrf-token': 'forged.token' },
    });
    expect(forged.statusCode).toBe(403);
  });

  it('accepts a cookie-authenticated POST that echoes the CSRF cookie', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/csrf-probe',
      headers: {
        cookie: cookieHeader(setCookie),
        'x-csrf-token': cookieValue(setCookie, CSRF_COOKIE),
      },
    });
    expect(res.statusCode).toBe(201);
  });

  it('accepts Bearer without a CSRF header', async () => {
    const token = await app.get(JwtService).signAsync({ sub: 'user-2', email: 'b@example.com' });
    const res = await app.inject({
      method: 'POST',
      url: '/csrf-probe',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(201);
  });

  // CORS-simple bodies skip preflight: Fastify refuses a body with no Content-Type (415) and
  // hands text/plain to Zod as a string (400) — neither reaches AuthService.login.
  it.each([
    { headers: {}, status: 415 },
    { headers: { 'content-type': 'text/plain' }, status: 400 },
  ])('refuses a non-JSON login body with $status', async ({ headers, status }) => {
    const res = await app.inject({
      method: 'POST',
      url: '/auth/session',
      headers,
      payload: JSON.stringify({ email: 'a@example.com', password: 'x'.repeat(12) }),
    });
    expect(res.statusCode).toBe(status);
  });

  it('clears both cookies on logout', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/logout' });
    expect(res.statusCode).toBe(204);
    const cleared = [res.headers['set-cookie'] ?? []].flat();
    for (const name of [SESSION_COOKIE, CSRF_COOKIE]) {
      expect(cleared.find((c) => c.startsWith(`${name}=`))).toMatch(/Expires=Thu, 01 Jan 1970/);
    }
  });
});

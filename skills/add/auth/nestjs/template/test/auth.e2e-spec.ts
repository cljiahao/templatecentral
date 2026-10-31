import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { JwtService } from '@nestjs/jwt';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Test } from '@nestjs/testing';
import { AppModule } from '../src/app.module';

describe('Auth (e2e)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication<NestFastifyApplication>(new FastifyAdapter());
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('rejects /auth/me without a token', async () => {
    const res = await app.inject({ method: 'GET', url: '/auth/me' });
    expect(res.statusCode).toBe(401);
  });

  it('returns the token subject on /auth/me', async () => {
    const token = await app.get(JwtService).signAsync({ sub: 'user-1', email: 'a@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: '/auth/me',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: 'user-1', email: 'a@example.com', roles: [] });
  });

  it('rejects a malformed login body', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/login', payload: { email: 'x' } });
    expect(res.statusCode).toBe(400);
  });
});

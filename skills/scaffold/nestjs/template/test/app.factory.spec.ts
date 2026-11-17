import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { createApp, resolveTrustProxy } from '../src/app.factory';

describe('resolveTrustProxy', () => {
  it('maps "*" to trust-every-hop', () => {
    expect(resolveTrustProxy('*')).toBe(true);
  });

  it.each([undefined, 'loopback', 'loopback,linklocal'])('passes %s through', (value) => {
    expect(resolveTrustProxy(value)).toBe(value);
  });
});

describe('createApp', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    ({ app } = await createApp());
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('serves the health route with security headers applied', async () => {
    const result = await app.inject({ method: 'GET', url: '/health' });
    expect(result.statusCode).toBe(200);
    expect(result.headers['x-content-type-options']).toBe('nosniff');
  });
});

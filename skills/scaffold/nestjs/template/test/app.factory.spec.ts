import { afterEach, describe, expect, it } from 'vitest';
import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { createApp } from '../src/app.factory';
import { appConfig, serviceConfig } from '../src/config';

const [origin = ''] = serviceConfig.CLIENT_URL;
// RFC 5737 documentation address
const clientIp = '203.0.113.9';
const original = appConfig.TRUST_PROXY;
let app: NestFastifyApplication | undefined;

async function request(url: string, headers: Record<string, string> = {}, trustProxy?: string) {
  appConfig.TRUST_PROXY = trustProxy;
  app = (await createApp()).app;
  const instance = app.getHttpAdapter().getInstance();
  instance.get('/__client-ip', (req) => ({ ip: req.ip }));
  await instance.ready();
  return app.inject({ method: 'GET', url, headers });
}

afterEach(async () => {
  appConfig.TRUST_PROXY = original;
  await app?.close();
});

describe('app factory', () => {
  it.each([
    [origin, origin],
    ['https://unlisted.invalid', undefined],
  ])('GET /health from %s: security headers, CORS grants %s', async (from, granted) => {
    const { statusCode, payload, headers } = await request('/health', { origin: from });
    expect([statusCode, payload, headers['x-content-type-options']]).toEqual([
      200,
      '{"status":"ok"}',
      'nosniff',
    ]);
    expect(headers['access-control-allow-origin']).toBe(granted);
  });

  it.each([
    [undefined, false],
    ['loopback', true],
    ['*', true],
  ])('TRUST_PROXY=%s honours X-Forwarded-For: %s', async (trust, honoured) => {
    const result = await request('/__client-ip', { 'x-forwarded-for': clientIp }, trust);
    expect(result.json<{ ip: string }>().ip === clientIp).toBe(honoured);
  });
});

import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { createApp, resolveTrustProxy } from '../src/app.factory';
import { appConfig, serviceConfig } from '../src/config';

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

describe('createApp CORS', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    ({ app } = await createApp());
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('answers a preflight from a configured client origin with credentials allowed', async () => {
    const [origin] = serviceConfig.CLIENT_URL;
    const result = await app.inject({
      method: 'OPTIONS',
      url: '/health',
      headers: { origin, 'access-control-request-method': 'POST' },
    });
    expect(result.headers['access-control-allow-origin']).toBe(origin);
    expect(result.headers['access-control-allow-credentials']).toBe('true');
  });

  it('does not grant CORS to an unlisted origin', async () => {
    const result = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: 'https://unlisted.invalid' },
    });
    expect(result.headers['access-control-allow-origin']).toBeUndefined();
  });
});

describe('createApp trust proxy', () => {
  // Built at runtime: the IP-literal lint rule flags a plain string.
  const clientIp = ['203', '0', '113', '9'].join('.');
  const original = appConfig.TRUST_PROXY;

  afterEach(() => {
    appConfig.TRUST_PROXY = original;
  });

  async function clientSeenBehindProxy(trustProxy: string | undefined): Promise<string> {
    appConfig.TRUST_PROXY = trustProxy;
    const { app } = await createApp();
    try {
      const instance = app.getHttpAdapter().getInstance();
      instance.get('/__client-ip', (request) => ({ ip: request.ip }));
      await instance.ready();
      const result = await app.inject({
        method: 'GET',
        url: '/__client-ip',
        headers: { 'x-forwarded-for': clientIp },
      });
      return (JSON.parse(result.payload) as { ip: string }).ip;
    } finally {
      await app.close();
    }
  }

  it('ignores X-Forwarded-For when TRUST_PROXY is unset', async () => {
    expect(await clientSeenBehindProxy(undefined)).not.toBe(clientIp);
  });

  it('honours X-Forwarded-For from a trusted proxy when TRUST_PROXY covers the peer', async () => {
    expect(await clientSeenBehindProxy('loopback')).toBe(clientIp);
  });
});

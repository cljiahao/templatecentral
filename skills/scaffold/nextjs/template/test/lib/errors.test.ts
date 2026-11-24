import { NextRequest } from 'next/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { APIError } from '@/integrations/error';
import { handleApiError, logError } from '@/lib/errors';
import { logger } from '@/lib/logger';
import { getAppOrigin } from '@/lib/utils/request-origin';

describe('APIError', () => {
  const circular: Record<string, unknown> = {};
  circular.self = circular;

  it.each([
    ['a trimmed string', '  boom  ', 'boom'],
    ['a record without a message', { code: 7 }, '{"code":7}'],
    ['an unserializable record', circular, '[unserializable]'],
  ])('builds its message from %s', (_label, data, message) => {
    const error = new APIError({ statusCode: 418, data });
    expect([error.message, error.statusCode]).toEqual([message, 418]);
  });
});

describe('error handling', () => {
  beforeEach(() => {
    vi.spyOn(logger, 'error').mockImplementation(() => undefined);
  });

  it.each([
    [new APIError({ statusCode: 404 }), 404, 'Resource not found'],
    [new Error('boom'), 500, 'lookup'],
    ['plain', 500, 'lookup'],
  ])('maps %s to a safe response', async (error, status, message) => {
    const res = handleApiError('lookup', error);
    expect(res.status).toBe(status);
    await expect(res.json()).resolves.toEqual({ error: message });
  });

  it('logs status for API errors and only the message otherwise', () => {
    logError('a', new APIError({ statusCode: 502, data: 'down' }));
    logError('b', new Error('oops'));
    logError('c', 'text');
    expect(vi.mocked(logger.error).mock.calls.map(([entry]) => entry)).toEqual([
      { label: 'a', message: 'down', statusCode: 502 },
      { label: 'b', message: 'oops' },
      { label: 'c', message: 'text' },
    ]);
  });
});

describe('getAppOrigin', () => {
  const request = new NextRequest('http://internal:3000/x', {
    headers: { 'x-forwarded-proto': 'https, http', 'x-forwarded-host': 'app.example' },
  });

  it.each([
    ['ignores forwarded headers unless TRUST_PROXY is set', '', 'http://internal:3000'],
    ['uses the first forwarded hop when TRUST_PROXY is set', '1', 'https://app.example'],
  ])('%s', (_label, trust, origin) => {
    vi.stubEnv('TRUST_PROXY', trust);
    expect(getAppOrigin(request)).toBe(origin);
  });

  afterEach(() => vi.unstubAllEnvs());
});

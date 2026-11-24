import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { APIError, logError } from '@/lib/errors';
import { FetchClient } from './fetch-client';

class TestClient extends FetchClient {
  call<T>(...args: Parameters<FetchClient['request']>) {
    return this.request<T>(...args);
  }
}

const client = new TestClient('http://api.test', { 'X-Key': 'k' });

function reply(body: BodyInit | null, status: number, type?: string, statusText = '') {
  const headers = type ? { 'Content-Type': type } : undefined;
  const res = new Response(body, { status, statusText, headers });
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(res));
}

describe('FetchClient', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => vi.unstubAllGlobals());

  it('sends the query, headers and JSON body, and parses a JSON reply', async () => {
    reply('{"ok":true}', 200, 'application/json');
    const out = await client.call('/items', 'POST', { a: 1 }, { page: 2, skip: undefined });
    const [url, init] = vi.mocked(fetch).mock.calls[0];
    expect(String(url)).toBe('http://api.test/items?page=2');
    expect(init?.headers).toEqual({ 'X-Key': 'k', 'Content-Type': 'application/json' });
    expect([init?.body, out]).toEqual(['{"a":1}', { ok: true }]);
  });

  it('sends FormData without a Content-Type so the browser adds the boundary', async () => {
    reply(null, 204);
    const form = new FormData();
    await client.call('upload', 'POST', form, {}, new AbortController().signal);
    expect(vi.mocked(fetch).mock.calls[0][1]?.headers).toEqual({ 'X-Key': 'k' });
  });

  it.each([
    ['text', 'hello', 200, 'text/plain', 'hello'],
    ['json fallback', new TextEncoder().encode('{"n":1}'), 200, undefined, { n: 1 }],
    ['text fallback', new TextEncoder().encode('plain'), 200, undefined, 'plain'],
    ['no content', null, 204, undefined, undefined],
  ])('parses a %s reply', async (_label, body, status, type, expected) => {
    reply(body, status, type);
    await expect(client.call('x')).resolves.toEqual(expected);
  });

  it.each([
    ['JSON', '{"message":"nope"}', 'application/json', 'nope'],
    ['unreadable JSON', 'oops', 'application/json', 'Bad Request'],
    ['HTML', '<html></html>', 'text/html', 'Bad Request'],
    ['plain text', 'denied', 'text/plain', 'denied'],
  ])('turns a %s error body into an APIError', async (_label, body, type, message) => {
    reply(body, 400, type, 'Bad Request');
    await expect(client.call('x')).rejects.toMatchObject({ statusCode: 400, message });
  });
});

describe('logError', () => {
  it('logs the status of API errors and only the message otherwise', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    logError('a', new APIError({ statusCode: 502, data: 'down' }));
    logError('b', new Error('oops'));
    logError('c', { error: 'text' });
    expect(spy.mock.calls.map(([label, entry]) => [label, entry.message])).toEqual([
      ['a:', 'down'],
      ['b:', 'oops'],
      ['c:', '[object Object]'],
    ]);
  });
});

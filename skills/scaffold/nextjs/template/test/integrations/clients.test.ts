import type { AxiosAdapter, AxiosResponse } from 'axios';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createAxiosClient } from '@/integrations/clients/base/axios-client';
import { FetchClient } from '@/integrations/clients/base/fetch-client';

class TestClient extends FetchClient {
  call<T>(...args: Parameters<FetchClient['request']>) {
    return this.request<T>(...args);
  }
}

const client = new TestClient('http://api.test', { 'X-Key': 'k' });

function reply(body: BodyInit | null, status: number, type?: string) {
  const headers = type ? { 'Content-Type': type } : undefined;
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(body, { status, headers })));
}

beforeEach(() => {
  vi.spyOn(console, 'log').mockImplementation(() => undefined);
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
});
afterEach(() => vi.unstubAllGlobals());

describe('FetchClient', () => {
  it('sends the query, headers and JSON body, and parses a JSON reply', async () => {
    reply('{"ok":true}', 200, 'application/json');
    const out = await client.call('items', 'POST', { a: 1 }, { page: 2, skip: undefined });
    const [url, init] = vi.mocked(fetch).mock.calls[0] ?? [];
    expect(String(url)).toBe('http://api.test/items?page=2');
    expect(init?.headers).toEqual({ 'X-Key': 'k', 'Content-Type': 'application/json' });
    expect([init?.body, out]).toEqual(['{"a":1}', { ok: true }]);
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
  ])('turns a %s error body into an APIError', async (_label, body, type, message) => {
    const res = new Response(body, {
      status: 400,
      statusText: 'Bad Request',
      headers: type ? { 'Content-Type': type } : undefined,
    });
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(res));
    await expect(client.call('x')).rejects.toMatchObject({ statusCode: 400, message });
  });
});

describe('createAxiosClient', () => {
  const adapter =
    (status: number, data: unknown): AxiosAdapter =>
    async (config) => {
      const res = { data, status, statusText: 'S', headers: {}, config } as AxiosResponse;
      if (status < 400) return res;
      throw Object.assign(new Error('failed'), { config, response: res, isAxiosError: true });
    };

  it('adds the API key header and logs when logging is enabled', async () => {
    const api = createAxiosClient({
      baseURL: 'http://api.test',
      apiKey: { 'X-Api-Key': 'k' },
      enableLogging: true,
      httpsAgentOptions: {},
    });
    api.defaults.adapter = async (config) => {
      expect(config.headers['X-Api-Key']).toBe('k');
      return adapter(200, 'fine')(config);
    };
    expect((await api.get('/x')).data).toBe('fine');
    expect(console.log).toHaveBeenCalledTimes(2);
  });

  it.each([
    ['a JSON body', { message: 'gone' }, 'gone'],
    ['an HTML body', '<html>', 'S'],
  ])('rejects %s with an APIError', async (_label, data, message) => {
    const api = createAxiosClient({ baseURL: 'http://api.test', enableLogging: true });
    api.defaults.adapter = adapter(404, data);
    await expect(api.get('/x')).rejects.toMatchObject({ statusCode: 404, message });
  });

  it('maps a timeout to 408', async () => {
    const api = createAxiosClient({ baseURL: 'http://api.test' });
    api.defaults.adapter = async () => {
      throw Object.assign(new Error('net'), { code: 'ECONNABORTED', isAxiosError: true });
    };
    await expect(api.get('/x')).rejects.toMatchObject({ statusCode: 408 });
  });
});

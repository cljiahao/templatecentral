import { describe, expect, it } from 'vitest';

import { GET as getRootHealth } from '@/app/api/route';
import { GET as getHealthPath } from '@/app/api/health/route';

function makeRequest(url: string): Request {
  return new Request(url);
}

describe('GET /api (root health)', () => {
  it('returns ok with 200', async () => {
    const response = await getRootHealth(makeRequest('http://localhost/api'));
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});

describe('GET /api/health (Docker / probe path)', () => {
  it('returns ok with 200', async () => {
    const response = await getHealthPath(makeRequest('http://localhost/api/health'));
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});

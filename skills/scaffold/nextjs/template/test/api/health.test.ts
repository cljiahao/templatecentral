import { describe, expect, it } from 'vitest';
import { NextRequest } from 'next/server';

import { GET as getHealthPath } from '@/app/api/health/route';

function makeRequest(url: string): NextRequest {
  return new NextRequest(url);
}

describe('GET /api/health (Docker / probe path)', () => {
  it('returns ok with 200', async () => {
    const response = await getHealthPath(makeRequest('http://localhost/api/health'));
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});

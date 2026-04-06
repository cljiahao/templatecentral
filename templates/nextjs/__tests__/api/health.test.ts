import { describe, expect, it } from 'vitest';

import { GET } from '@/app/api/route';

describe('GET /api (health check)', () => {
  it('should return status ok with 200', async () => {
    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});

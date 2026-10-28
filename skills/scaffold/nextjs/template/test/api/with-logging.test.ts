import { describe, expect, it } from 'vitest';
import { NextRequest, NextResponse } from 'next/server';

import { type RouteContext, withLogging } from '@/lib/utils/with-logging';

function makeRequest(url: string): NextRequest {
  return new NextRequest(url);
}

describe('withLogging', () => {
  it('returns the handler response on success', async () => {
    const GET = withLogging(async () => NextResponse.json({ ok: true }, { status: 201 }));
    const res = await GET(makeRequest('http://localhost/api/thing'));
    expect(res.status).toBe(201);
    await expect(res.json()).resolves.toEqual({ ok: true });
  });

  it('catches a thrown error and returns a 500 without leaking the message', async () => {
    const GET = withLogging(async () => {
      throw new Error('boom');
    });
    const res = await GET(makeRequest('http://localhost/api/thing'));
    expect(res.status).toBe(500);
    await expect(res.json()).resolves.toEqual({ error: 'Internal server error' });
  });

  it('passes typed dynamic-route params through to the handler', async () => {
    const GET = withLogging<RouteContext<{ id: string }>>(async (_req, { params }) => {
      const { id } = await params;
      return NextResponse.json({ id });
    });
    const res = await GET(makeRequest('http://localhost/api/thing/42'), {
      params: Promise.resolve({ id: '42' }),
    });
    await expect(res.json()).resolves.toEqual({ id: '42' });
  });
});

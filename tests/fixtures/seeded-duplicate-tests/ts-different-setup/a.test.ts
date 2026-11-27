import { beforeEach, describe, expect, it, vi } from 'vitest';
import { compute } from './lib';

describe('with the cache', () => {
  beforeEach(() => {
    vi.stubEnv('CACHE', 'on');
  });
  it('sums', () => {
    const r = compute(1, 2);
    expect(r.total).toBe(3);
    expect(r.items.length).toBe(2);
  });
});

describe('without the cache', () => {
  beforeEach(() => {
    vi.stubEnv('CACHE', 'off');
  });
  it('sums', () => {
    const r = compute(1, 2);
    expect(r.total).toBe(3);
    expect(r.items.length).toBe(2);
  });
});

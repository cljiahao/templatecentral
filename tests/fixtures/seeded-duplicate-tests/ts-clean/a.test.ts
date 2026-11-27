import { describe, expect, it } from 'vitest';
import { compute } from './lib';

describe('compute', () => {
  it('sums', () => {
    const r = compute(1, 2);
    expect(r.total).toBe(3);
    expect(r.items.length).toBe(2);
  });

  it('rejects negatives', () => {
    expect(() => compute(-1, 2)).toThrow('negative');
  });

  it('multiplies when asked', () => {
    const r = compute(3, 4, { mode: 'product' });
    expect(r.total).toBe(12);
    expect(r.items).toEqual([3, 4]);
  });
});

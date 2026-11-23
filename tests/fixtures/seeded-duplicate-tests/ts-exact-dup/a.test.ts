import { describe, expect, it } from 'vitest';
import { compute } from './lib';

describe('compute', () => {
  it('sums the first pair', () => {
    const r = compute(1, 2);
    expect(r.total).toBe(3);
    expect(r.items.length).toBe(2);
  });

  it.skip('adds the numbers again', () => {
    // same body, different spacing and a comment
    const r = compute(1, 2); expect(r.total).toBe(3);
    expect(r.items.length).toBe(2); /* trailing */
  });
});

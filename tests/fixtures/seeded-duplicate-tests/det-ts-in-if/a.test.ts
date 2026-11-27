import { expect, it } from 'vitest';
import { compute } from './lib';
if (process.env.FULL) {
  it('one', () => {
    expect(compute(1)).toBe(2);
    expect(compute(2)).toBe(4);
  });
  it('two', () => {
    expect(compute(1)).toBe(2);
    expect(compute(2)).toBe(4);
  });
}

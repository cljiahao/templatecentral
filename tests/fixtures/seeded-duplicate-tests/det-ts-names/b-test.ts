import { expect, it } from 'vitest';
import { compute } from './lib';
it('one', () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
});

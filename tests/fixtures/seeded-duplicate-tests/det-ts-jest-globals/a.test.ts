import { expect, it } from '@jest/globals';
import { compute } from './lib';
it('one', () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
});
it('two', () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
});

import * as v from 'vitest';
import { compute } from './lib';
v.it('one', () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
});
v.test('two', () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
});

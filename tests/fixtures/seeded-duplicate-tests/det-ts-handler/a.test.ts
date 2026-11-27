import { expect, it } from 'vitest';
import { compute } from './lib';
function one() {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
}
const two = () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
};
it('one', one);
it('two', two);

import { expect, it } from 'vitest';
import { double } from './lib';

it('doubles one', () => {
  expect(double(1)).toBe(2);
});
it('doubles two', () => {
  expect(double(2)).toBe(4);
});
it('doubles three', () => {
  expect(double(3)).toBe(6);
});
it('doubles four', () => {
  expect(double(4)).toBe(8);
});

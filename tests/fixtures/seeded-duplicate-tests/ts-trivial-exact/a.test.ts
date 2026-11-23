import { expect, it } from 'vitest';
import { double } from './lib';

it('doubles one', () => {
  expect(double(1)).toBe(2);
});
it('doubles one again', () => {
  expect(double(1)).toBe(2);
});

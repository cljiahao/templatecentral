import { it as t, expect } from 'vitest';
import { compute } from './lib';
t('one', () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
});
t('two', () => {
  expect(compute(1)).toBe(2);
  expect(compute(2)).toBe(4);
});

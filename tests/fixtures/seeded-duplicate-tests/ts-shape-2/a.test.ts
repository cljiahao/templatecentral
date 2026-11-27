import { expect, it } from 'vitest';
import { compute } from './lib';

it('sums one', () => {
  const r = compute(1, 2);
  expect(r.total).toBe(3);
  expect(r.items.length).toBe(2);
});

it('sums two', () => {
  const r = compute(10, 20);
  expect(r.total).toBe(30);
  expect(r.items.length).toBe(2);
});

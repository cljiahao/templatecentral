import { expect, it } from 'vitest';
import { compute } from './lib';

it('sums two', () => {
  const r = compute(10, 20);
  expect(r.total).toBe(30);
  expect(r.items.length).toBe(2);
});

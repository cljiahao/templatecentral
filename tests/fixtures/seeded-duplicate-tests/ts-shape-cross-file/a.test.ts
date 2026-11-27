import { expect, it } from 'vitest';
import { compute } from './lib';

it('sums one', () => {
  const r = compute(1, 2);
  expect(r.total).toBe(3);
  expect(r.items.length).toBe(2);
});

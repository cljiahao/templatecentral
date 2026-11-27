import { expect, it } from 'vitest';
import { compute } from './lib';

it('sums three', () => {
  const r = compute(7, 8);
  expect(r.total).toBe(15);
  expect(r.items.length).toBe(2);
});

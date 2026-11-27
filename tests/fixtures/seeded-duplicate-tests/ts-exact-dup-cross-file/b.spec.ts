import { expect, test } from 'vitest';
import { compute } from './lib';

test.only('second copy with another title', () => {
  const r = compute(4, 5);
  expect(r.total).toBe(9);
});

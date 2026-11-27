import { expect, test } from 'vitest';
import { compute } from './lib';

test('first copy', () => {
  const r = compute(4, 5);
  expect(r.total).toBe(9);
});

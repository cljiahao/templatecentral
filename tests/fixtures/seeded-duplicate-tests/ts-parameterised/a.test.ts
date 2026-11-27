import { expect, it, test } from 'vitest';
import { compute } from './lib';

it.each([[1, 2, 3], [10, 20, 30]])('sums %i + %i', (a, b, total) => {
  const r = compute(a, b);
  expect(r.total).toBe(total);
  expect(r.items.length).toBe(2);
});

test.each([[2, 3, 5], [10, 20, 30]])('sums again %i + %i', (a, b, total) => {
  const r = compute(a, b);
  expect(r.total).toBe(total);
  expect(r.items.length).toBe(2);
});

it.each([[1, 2, 3]])('sums a third time %i + %i', (a, b, total) => {
  const r = compute(a, b);
  expect(r.total).toBe(total);
  expect(r.items.length).toBe(2);
});

it.each`
  a | b | total
  ${1} | ${2} | ${3}
`('tagged $a + $b', ({ a, b, total }) => {
  const r = compute(a, b);
  expect(r.total).toBe(total);
  expect(r.items.length).toBe(2);
});

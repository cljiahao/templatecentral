import { it, expect } from 'vitest';
import { f } from './a';
it('runs', () => {
  const result = f();
  expect(result.total).toBe(3);
  expect(result.items.length).toBe(2);
});

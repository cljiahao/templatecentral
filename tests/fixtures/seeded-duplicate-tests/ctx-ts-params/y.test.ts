import { expect, it } from 'vitest';
import { svc as base } from './lib';
it('runs', async ({ request }) => {
  expect(base.run(1)).toBe(2);
  expect(base.run(2)).toBe(4);
});

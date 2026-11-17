import { expect, it, vi } from 'vitest';

const runBootstrap = vi.hoisted(() => vi.fn());
vi.mock('../src/bootstrap', () => ({ runBootstrap }));

it('main.ts starts the app through runBootstrap', async () => {
  await import('../src/main.js');
  expect(runBootstrap).toHaveBeenCalledTimes(1);
});

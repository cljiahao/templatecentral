import { defineConfig } from 'vitest/config';

const base = { test: { coverage: { exclude: ['**'] } } };

export default defineConfig({
  ...base,
  test: {
    globals: true,
  },
});

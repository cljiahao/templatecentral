import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      // reason: the allow-list keeps coverage on hand written source
      include: ['src/**/*.ts'],
      thresholds: { lines: 60, functions: 80 },
    },
  },
});

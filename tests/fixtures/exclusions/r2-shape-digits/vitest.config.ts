import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: 123 456 789
        'src/gen/**',
      ],
    },
  },
});

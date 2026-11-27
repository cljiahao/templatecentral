import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: a b c
        'src/gen/**',
      ],
    },
  },
});

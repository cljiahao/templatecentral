import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: generated xxx client
        'src/gen/**',
      ],
    },
  },
});

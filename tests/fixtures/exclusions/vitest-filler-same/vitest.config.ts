import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: client client client
        'src/gen/**',
      ],
    },
  },
});

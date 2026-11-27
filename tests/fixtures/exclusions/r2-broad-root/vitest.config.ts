import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: generated client code is not hand written
        'src/**',
      ],
    },
  },
});

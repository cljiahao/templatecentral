import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: aaa bbb ccc
        'src/gen/**',
      ],
    },
  },
});

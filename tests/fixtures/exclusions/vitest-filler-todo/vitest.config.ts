import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: TODO TODO TODO
        'src/gen/**',
      ],
    },
  },
});

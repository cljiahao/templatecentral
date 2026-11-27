import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: tbd tbd tbd
        'src/gen/**',
      ],
    },
  },
});

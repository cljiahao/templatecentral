import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: fix me later please
        'src/gen/**',
      ],
    },
  },
});

import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: FIXME later please
        'src/gen/**',
      ],
    },
  },
});

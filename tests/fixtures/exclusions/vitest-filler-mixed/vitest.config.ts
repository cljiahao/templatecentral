import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: TODO replace this soon
        'src/gen/**',
      ],
    },
  },
});

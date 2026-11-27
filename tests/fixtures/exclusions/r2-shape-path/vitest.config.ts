import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: src api handlers
        'src/api/handlers/**',
      ],
    },
  },
});

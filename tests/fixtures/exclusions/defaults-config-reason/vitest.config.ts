import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: tool configs at any depth are not shipped
        '**/*.config.*',
      ],
    },
  },
});

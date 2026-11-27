import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: the vendored build tool output is not ours
        '**/build/**',
      ],
    },
  },
});

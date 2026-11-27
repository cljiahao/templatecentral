import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: the handler folder holds generated stubs
        'src/api/handlers/**',
      ],
    },
  },
});

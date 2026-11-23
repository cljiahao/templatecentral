import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        '*.config.{js,ts,mjs,cjs}',
        'test/**',
        '**/*.d.ts',
      ],
    },
  },
});

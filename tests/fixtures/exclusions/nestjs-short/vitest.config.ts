import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      // reason: the allow-list keeps coverage on hand written source
      include: ['src/**/*.ts'],
      exclude: [
        // reason: generated code
        'src/gen/**',
        '**/*.d.ts',
      ],
      thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
    },
  },
});

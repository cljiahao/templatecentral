import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      // reason: the allow-list keeps coverage on hand written source
      include: ['src/**/*.ts'],
      exclude: [
        'src/gen/**',
        // reason: generated client code is not hand written
        '**/*.d.ts',
      ],
      thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
    },
  },
});

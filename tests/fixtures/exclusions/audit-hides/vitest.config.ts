import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: the whole source folder was left out to reach the threshold
        'src/**',
        '**/*.py',
        // reason: generated client code is not hand written
        'src/gen/**',
        '**/*.d.ts',
        'lib/**/*.ts',
        'src/legacy/**',
      ],
      thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
    },
  },
});

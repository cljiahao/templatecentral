import { defineConfig } from 'vitest/config';

const buildExcludes = () => ['src/gen/**'];
export default defineConfig({
  test: {
    coverage: {
      // reason: the allow-list keeps coverage on hand written source
      include: ['src/**/*.ts'],
      exclude: buildExcludes(),
      thresholds: { lines: 80, functions: 80, branches: 80, statements: 80 },
    },
  },
});

import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // exclude: ['src/hidden/**'] was the old list
    name: "coverage: { exclude: ['src/secret/**'] }",
    coverage: {
      // reason: the allow-list keeps coverage on hand written source
      include: ['src/**/*.ts'],
      exclude: ['**/*.d.ts'],
      thresholds: { lines: 80 },
    },
  },
});

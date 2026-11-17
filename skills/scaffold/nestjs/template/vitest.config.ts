import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: false,
    environment: 'node',
    passWithNoTests: true,
    // CI runners are small: half the cores per process keeps memory flat; sharding adds the parallelism.
    maxWorkers: process.env.CI ? '50%' : undefined,
    include: ['test/**/*.{spec,test}.ts', 'src/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura', 'lcov'],
      include: ['src/**/*.ts'],
      exclude: ['**/*.spec.ts', '**/*.d.ts'],
    },
  },
});

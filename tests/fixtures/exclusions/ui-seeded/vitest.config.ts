import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      // reason: the allow-list keeps coverage on hand written source
      include: ['src/**/*.ts'],
      exclude: [
        // reason: shadcn primitives are vendored and covered upstream
        'src/components/ui/**',
        '**/*.d.ts',
      ],
      thresholds: { lines: 80 },
    },
  },
});

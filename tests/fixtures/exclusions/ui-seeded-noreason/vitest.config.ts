import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      // reason: the allow-list keeps coverage on hand written source
      include: ['src/**/*.ts'],
      exclude: [
        'src/components/ui/**',
        '**/*.d.ts',
      ],
      thresholds: { lines: 80 },
    },
  },
});

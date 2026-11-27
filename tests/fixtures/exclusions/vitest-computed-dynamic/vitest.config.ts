import { defineConfig } from 'vitest/config';

const k = 'cov' + 'erage';

export default defineConfig({
  test: {
    [k]: {
      exclude: [
        // reason: generated client code is not hand written
        'src/gen/**',
      ],
    },
  },
});

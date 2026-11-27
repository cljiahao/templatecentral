export const base = {
  test: {
    coverage: {
      exclude: [
        // reason: generated client code is not hand written
        'src/gen/**',
      ],
    },
  },
};

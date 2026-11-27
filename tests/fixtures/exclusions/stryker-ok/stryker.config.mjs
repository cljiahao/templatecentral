export default {
  mutate: [
    'src/**/*.ts',
    // reason: integration clients are covered by contract tests
    '!src/integrations/**',
  ],
};

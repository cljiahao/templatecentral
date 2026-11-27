module.exports = {
  coverageThreshold: { global: { lines: 80 } },
  coveragePathIgnorePatterns: [
    // reason: generated client code is not hand written
    '<rootDir>/src/gen/',
    '/node_modules/',
  ],
};

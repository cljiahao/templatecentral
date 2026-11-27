module.exports = {
  // reason: only the source folder is measured by this project
  collectCoverageFrom: [
    'src/**/*.js',
    // reason: generated client code is not hand written
    '!src/gen/**',
  ],
};

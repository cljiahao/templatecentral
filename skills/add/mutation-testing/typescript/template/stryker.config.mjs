/** @type {import('@stryker-mutator/core').PartialStrykerOptions} */
const config = {
  testRunner: "vitest",
  // Required under pnpm: plugin discovery finds nothing in the isolated node_modules.
  plugins: ["@stryker-mutator/vitest-runner"],
  coverageAnalysis: "perTest",
  reporters: ["html", "clear-text", "progress", "json"],
  htmlReporter: { fileName: "stryker-report.html" },
  jsonReporter: { fileName: "stryker-report.json" },
  // An explicit mutate glob avoids mutating files the test policy never covers.
  mutate: ["src/**/*.ts", "src/**/*.tsx", "!src/**/*.test.ts", "!src/**/*.test.tsx"],
  // Report only; set break to a number to enforce a kill-rate floor.
  thresholds: { break: null },
};

export default config;

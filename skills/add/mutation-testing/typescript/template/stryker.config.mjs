/** @type {import('@stryker-mutator/core').PartialStrykerOptions} */
const config = {
  testRunner: "vitest",
  // Required under pnpm: Stryker's default plugin discovery ("@stryker-mutator/*" next to
  // @stryker-mutator/core) finds nothing in pnpm's isolated node_modules layout and fails with
  // `Cannot find TestRunner plugin "vitest"`. Naming the runner explicitly loads it.
  plugins: ["@stryker-mutator/vitest-runner"],
  coverageAnalysis: "perTest",
  reporters: ["html", "clear-text", "progress", "json"],
  htmlReporter: { fileName: "stryker-report.html" },
  jsonReporter: { fileName: "stryker-report.json" },
  // Without an explicit mutate glob Stryker mutates everything under src/, including
  // files the project's test policy never covers — every such mutant survives and
  // drags the kill rate down for no signal. Replace with your stack's row below.
  mutate: ["src/**/*.ts", "src/**/*.tsx", "!src/**/*.test.ts", "!src/**/*.test.tsx"],
  // report-only: set break to a number (e.g. 70) to enforce a kill-rate floor
  thresholds: { break: null },
};

export default config;

<!-- ref: add/mutation-testing/typescript.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as Next.js, NestJS, or Vite+React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## TypeScript Stacks — Mutation Testing (StrykerJS)

Add report-only mutation testing to a TypeScript project scaffolded from templateCentral. Uses StrykerJS + the Vitest runner (install resolves the current major).

> **Report-only by default.** `thresholds.break` is `null` — results appear in CI output and `stryker-report.html` without failing the build. To enforce a floor, change `break` to a number (e.g., `70`).

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold` for Next.js, NestJS, or Vite+React. See Step 0.

### Dependencies

Add to `package.json` devDependencies:
- `@stryker-mutator/core` — mutation testing framework
- `@stryker-mutator/vitest-runner` — Vitest integration

```bash
pnpm add -D @stryker-mutator/core @stryker-mutator/vitest-runner
```

### Steps

#### Step 0 — Verify context

Check `AGENTS.md` line 1 for `<!-- templateCentral:`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### Step 1 — Create StrykerJS config

Create `stryker.config.mjs` at the project root:

```javascript
/** @type {import('@stryker-mutator/core').PartialStrykerOptions} */
const config = {
  testRunner: "vitest",
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
```

Set `mutate` to match what your stack's test policy actually covers:

| Stack | `mutate` |
|---|---|
| Next.js | `["src/app/api/**/*.ts"]` — the test policy covers API routes under `src/app/api/**`, not React UI |
| NestJS | `["src/**/*.ts", "!src/main.ts"]` — all backend code except the bootstrap entrypoint |
| Vite + React | the default above — tests are co-located, so the `!src/**/*.test.*` exclusions are required (an explicit `mutate` overrides Stryker's built-in test-file exclusion) |

#### Step 2 — Add npm script

Add to `package.json` `"scripts"`:

```json
"mutation": "stryker run"
```

#### Step 3 — Update .gitignore

Append to `.gitignore`:

```
# Stryker mutation testing
.stryker-tmp/
stryker-report.html
stryker-report.json
```

#### Step 4 — Add CI job

If `.github/workflows/` exists, add a `mutation` job to the primary workflow. It runs after tests pass and never fails the build:

```yaml
  mutation:
    runs-on: ubuntu-latest
    needs: [test]
    continue-on-error: true
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      # No `version:` — reads packageManager from package.json, matching the scaffold's CI.
      - uses: pnpm/action-setup@a15d269cd4658e1107c09f1fabf4cbd7bd1f308a # v4.4.0
      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
        with:
          node-version: "24"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile
      - run: pnpm mutation
```

### Validate

```bash
pnpm mutation    # runs StrykerJS; kill-rate score in terminal; HTML report at stryker-report.html
```

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — confirm no compile errors after config addition
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check config correctness

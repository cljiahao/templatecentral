<!-- ref: add/mutation-testing/typescript.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as Next.js, NestJS, or Vite+React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## TypeScript Stacks — Mutation Testing (StrykerJS)

Report-only mutation testing with StrykerJS + the Vitest runner.

> **Report-only by default.** `thresholds.break` is `null` — results appear in CI output and `stryker-report.html` without failing the build. To enforce a floor, change `break` to a number (e.g., `70`).

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold` for Next.js, NestJS, or Vite+React.

### Dependencies

Add to `package.json` devDependencies:
- `@stryker-mutator/core` — mutation testing framework
- `@stryker-mutator/vitest-runner` — Vitest integration

```bash
pnpm add -D @stryker-mutator/core @stryker-mutator/vitest-runner
```

### Steps

#### Step 1 — Create StrykerJS config

Run `TC_PART=leaf TC_LEAF=add/mutation-testing/typescript bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/mutation-testing/typescript/template/` (listed in `<skill-dir>/mutation-testing/typescript/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

`stryker.config.mjs` at the project root (copied above).

Set `mutate` to match what your stack's test policy covers:

| Stack | `mutate` |
|---|---|
| Next.js | `["src/app/api/**/*.ts"]` — the test policy covers API routes under `src/app/api/**`, not React UI |
| NestJS | `["src/**/*.ts", "!src/main.ts"]` — all backend code except the `main.ts` entrypoint (it only calls `runBootstrap()`; `src/bootstrap.ts` is tested and mutated) |
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
      - uses: pnpm/action-setup@73e46992e05b19abd31f2f3c20e0e7370d762115 # v6.1.1
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: "26"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile
      - run: pnpm mutation
```

### Validate

```bash
pnpm mutation    # runs StrykerJS; kill-rate score in terminal; HTML report at stryker-report.html
```

---
name: shared-update-agent
description: Use when updating project dependencies to latest compatible versions after scaffolding or when convention drift is detected
---

# Update Agent

Fetch latest dependency versions from npm or PyPI, apply patch/minor bumps, roll back failures, report major bumps.

## Stack Detection

Same as `build-agent`: check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.

Node stacks (Next.js, Vite-React, NestJS): read `package.json`.
FastAPI: read `requirements.txt`.

## Steps

### Node Stacks

1. Read `package.json` — collect all keys from `dependencies` and `devDependencies`
2. For each package, WebFetch: `https://registry.npmjs.org/<package-name>/latest`
   - Extract `version` field from JSON response
3. Compare current version (strip `^` / `~` prefix) to registry `version` using semver:
   - **Patch or minor bump** → add to auto-update list
   - **Major bump** → add to report-only list
   - **Current** → skip
4. Rewrite `package.json` with bumped versions (keep `^` prefix for all updated deps)
5. Run `pnpm install`
6. Dispatch `build-agent`
7. If build fails → rollback (see Rollback below)
8. Run `pnpm audit --audit-level=high`
   - A non-zero exit due to found advisories is expected — record them and continue to step 9
   - If the command fails for a non-advisory reason (network error, registry unreachable): add "pnpm audit failed — security advisory check skipped" to the report and continue to step 9
   - Report any high/critical advisories under "Security advisories" in the results summary
   - Do NOT auto-rollback — advisories are report-only; the user decides next steps
9. Report results (see Reporting below)

### FastAPI

1. Read `requirements.txt`
2. For each package (parse `package==version` or `package>=version`), WebFetch: `https://pypi.org/pypi/<package>/json`
   - Extract `info.version` from JSON response
3. Compare versions:
   - **Patch or minor bump** → auto-update list
   - **Major bump** → report-only list
4. Rewrite `requirements.txt` with exact pinned versions (`package==new_version`)
5. Run `pip install -r requirements.txt`
6. Dispatch `build-agent`
7. If build fails → rollback
8. Run `pip-audit --requirement requirements.txt` if `pip-audit` is available
   - If `pip-audit` is not installed: add note "pip-audit not installed — security advisory check skipped" to report
   - Report any vulnerabilities under "Security advisories" in the results summary
   - Do NOT auto-rollback — advisories are report-only; the user decides next steps
9. Report results

## Rollback

If `build-agent` reports failure after applying all updates:

1. Save list of updated packages + old/new versions
2. Restore original `package.json` / `requirements.txt`
3. Restore one package at a time — re-apply all updates except one, run `pnpm install` / `pip install`, dispatch `build-agent`
4. Repeat until the breaking package is identified
5. Keep all updates except the breaking package
6. Report which package could not be updated and its current vs attempted version

## Reporting

If security advisories are found, list them under "Security advisories". If none found, omit the block entirely.

```
Update agent complete — Next.js

Updated (patch/minor):
- react 18.2.0 → 18.3.1
- @tanstack/react-query 5.17.0 → 5.24.0
- typescript 5.3.3 → 5.4.5

Major bumps (not applied — manual review needed):
- next 14.2.0 → 15.0.0  ← major upgrade, check release notes

Could not update (build failed after bump):
- some-package 2.1.0 → 2.3.0  ← rolled back, build broke

Build: passed

Security advisories:
- some-package 2.3.0: GHSA-xxxx-xxxx-xxxx (high) — upgrade to 2.3.1 or higher
```

## Callers

Dispatched by: `nextjs-scaffold`, `vite-react-scaffold`, `fastapi-scaffold`, `nestjs-scaffold`, `shared-drift-check` (when drift detected and user accepts update).

## Changelog
### 1.0.0
- Initial plugin release

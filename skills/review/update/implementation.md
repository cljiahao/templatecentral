<!-- ref: review/update/implementation.md
     loaded-by: review/SKILL.md
     prereq: Update agent workflow. Do not invoke this file directly — it is catted by agents via skills/review/SKILL.md (de-registered agent utility). -->

# Update Agent

Fetch latest dependency versions from npm or PyPI, apply patch/minor bumps, roll back failures, report major bumps.

## Stack Detection

Same as `build-agent`: check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.

Node stacks (Next.js, Vite-React, NestJS): read `package.json`.
FastAPI: read `requirements.txt`.

## Steps

### Node Stacks

1. Run `pnpm outdated --format json` from the project root — one command covers every package in `dependencies` and `devDependencies`
2. Parse the JSON output — each entry gives `current` and `latest` versions (packages not listed are already current)
   - WebFetch `https://registry.npmjs.org/<package-name>/latest` only as a fallback for packages needing release-note review
3. Compare `current` to `latest` using semver:
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

1. Read `requirements.txt` (parse `package==version` or `package>=version`)
2. Run `pip list --outdated --format json` — one command covers every installed package; cross-reference entries against `requirements.txt`
   - WebFetch `https://pypi.org/pypi/<package>/json` only as a fallback for packages needing release-note review
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
- <pkg-a> x.y.z → x.(y+1).0
- <pkg-b> x.y.z → x.y.(z+1)

Major bumps (not applied — manual review needed):
- <pkg-c> x.y.z → (x+1).0.0  ← major upgrade, check release notes

Could not update (build failed after bump):
- <pkg-d> x.y.z → x.(y+1).0  ← rolled back, build broke

Build: passed

Security advisories:
- <pkg-e> x.y.z: GHSA-xxxx-xxxx-xxxx (high) — upgrade to the patched version or higher
```

## Callers

Dispatched by: `templatecentral:scaffold` (all stacks), `templatecentral:standards` drift-check (when drift detected and user accepts update).

## Changelog
### 1.0.0
- Initial plugin release
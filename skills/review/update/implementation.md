<!-- ref: review/update/implementation.md
     loaded-by: review/SKILL.md
     prereq: Update agent workflow. Do not invoke this file directly — it is catted by agents via skills/review/SKILL.md (de-registered agent utility). -->

# Update Agent

Apply patch and minor dependency bumps, roll back what breaks the build, report major bumps and advisories. Dependabot (seeded `dependabot.yml`) covers routine bumps; this operation is for an on-demand sweep.

Read the stack from the `<!-- templateCentral: <stack>@` marker on `AGENTS.md` line 1; absent, ask the user.

**Never break a pin or floor:** an exact pin (e.g. a pre-release like `"drizzle-orm": "1.0.0-rc.4"`) stays exact and is only moved deliberately, never to a `^` range; never lower a version below the security floor in the plugin's `.claude/rules/<stack>.md`; keep `pnpm-workspace.yaml` overrides at or above their floors.

## Steps

1. List outdated packages: `pnpm outdated --format json` (Node stacks), or `pip list --outdated --format json` cross-referenced with `requirements.in` (FastAPI).
2. Apply patch and minor bumps only, keeping each specifier's style (`^` stays `^`, exact stays exact). Major bumps go to the report.
3. Install: `pnpm install`; FastAPI: `uv pip compile requirements.in --universal --generate-hashes -o requirements.txt`, then `pip install --require-hashes -r requirements.txt`.
4. Run the stack's check command (`pnpm check`; fastapi `python -m pyright src/ && ruff check src/`). On failure, restore the originals, re-apply all but one package and re-run it, rotating the excluded package until it passes; keep every update except the breaking one.
5. Audit: `pnpm audit --audit-level=high`, or `pip-audit --requirement requirements.txt` when installed (the scaffold does not install it; do not install it, note "pip-audit not installed — security advisory check skipped"). A non-zero exit from found advisories is expected. Advisories are report-only; never auto-rollback for them. If the audit fails for a non-advisory reason (for example no network), report it as skipped, not as passed.
6. List every entry in `.claude/dep-audit-allow.txt` and propose removing it once a fixed release exists or its documented reason no longer holds.

## Reporting

```
Update agent complete — Next.js

Updated (patch/minor):
- <pkg-a> x.y.z → x.(y+1).0

Major bumps (not applied — manual review needed):
- <pkg-c> x.y.z → (x+1).0.0  ← check release notes

Could not update (build failed after bump):
- <pkg-d> x.y.z → x.(y+1).0  ← rolled back

Build: passed

Security advisories:
- <pkg-e> x.y.z: GHSA-xxxx-xxxx-xxxx (high) — upgrade to the patched version or higher
```

Omit the "Security advisories" block when there are none.

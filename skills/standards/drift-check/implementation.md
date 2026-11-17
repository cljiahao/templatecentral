<!-- ref: standards/drift-check/implementation.md
     loaded-by: standards/SKILL.md
     prereq: Drift check workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->

# Drift Check

Compare the project's recorded templateCentral install version to the current plugin version, report convention drift, measure code quality, and optionally run dependency and security checks. Read-only except for run artefacts the measurements leave (deleted afterwards) and the scratch directory they use.

## Step 1 — Confirm a templateCentral project

Line 1 of the project's `AGENTS.md` must be the harness marker:

```
<!-- templateCentral: <stack>@<schema-version> -->
```

e.g. `<!-- templateCentral: nextjs@6.0.0 -->`. `@X.Y.Z` is the harness schema version, not the install version, so it is expected to stay put across plugin releases. Never compare it to the plugin semver; it only identifies `<stack>`.

No marker → not a templateCentral project. Exit silently.

## Step 2 — Read both versions

- **Project version**: `templatecentral_version` in the project's `.claude/harness.json`.
- **Plugin version**: `version` in `<skill-dir>/../../.claude-plugin/plugin.json` (the version SSOT).

**`.claude/harness.json` missing** → no recorded install version. Do not report drift; tell the user:

> "`.claude/harness.json` not found — this project has no recorded install version. To adopt the templateCentral harness, run `templatecentral:migrate`."

Skip Steps 3–4. Continue at Step 5 only if the request asked for a quality check; otherwise exit.

## Step 3 — Compare (semver `major.minor.patch`)

- Project version ≥ plugin version → conventions are current (or the installed plugin is older than the project). Skip Step 4. Go to Step 5 if the request asked for a quality check, and to Step 6 if `AGENTS.md` contains `<!-- templateCentral-check-deps -->`; otherwise exit silently.
- Project version < plugin version → drift. Continue.

## Step 4 — Convention drift report

Read `<skill-dir>/../../CHANGELOG.md`. Extract every entry newer than the project version that touches the detected stack, the shared harness, or skills the project uses. Also compare the project's pinned versions against the `Stack:` line in `<skill-dir>/../../.claude/rules/<stack>.md`.

Report the project and plugin versions, then the changelog lines since the install (grouped by version, stack-relevant only; never invent entries), then each stack floor the project does not meet (package, project value, floor). Convention updates are manual: say so.

## Step 5 — Quality (opt-in)

Ask first and state the cost: the run executes the project's tests with coverage plus lint, typecheck, complexity and duplication (up to 10 minutes per tool). Skip this step when the user declines.

On yes, load `cat "<skill-dir>/../migrate/general/quality-baseline.md"` and run its script with `--full`, only because the user said yes above; the script does not intentionally write to the project and its last row reports any write. Print the metric table, then up to five worst offenders per category with file paths. If `docs/quality-baseline.md` exists, compare against its latest column (`after` if present, else the baseline values) and mark each metric that moved the wrong way. Name each metric that misses the target and recommend `templatecentral:migrate` for the fix.

## Step 6 — Dependency drift (optional)

Ask:

> "Dependency drift check is available — it compares your declared dependencies against the latest registry versions. Run it? (y/n)"

If the user accepts, or the project `AGENTS.md` contains `<!-- templateCentral-check-deps -->`, dispatch the review utility's `update` operation (`cat "<skill-dir>/../review/SKILL.md"`). The marker skips the question and runs this step even when Step 3 found no convention drift.

## Step 7 — Security audit (optional)

Ask:

> "Security audit available — checks installed packages against advisory databases. Run it? (y/n)"

If accepted:

- **Node stacks**: `pnpm audit --audit-level=high`. Also list every entry in `.claude/dep-audit-allow.txt` and flag any whose advisory now has a fixed release or whose documented reason no longer holds; flag any `audit.ignore` / `auditConfig` in `pnpm-workspace.yaml` or `package.json` as a bypass the deps gate rejects.
- **FastAPI**: if `pip-audit --version` succeeds, run `pip-audit -r requirements.txt`; otherwise report "pip-audit not installed — security advisory check skipped". Review `.claude/dep-audit-allow.txt` the same way.

Zero findings → "No known vulnerabilities found." Otherwise list package, severity, advisory ID, and whether a fixed version exists, and recommend the review utility's `update` operation. Never auto-upgrade.

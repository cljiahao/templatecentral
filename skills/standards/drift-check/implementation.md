<!-- ref: standards/drift-check/implementation.md
     loaded-by: standards/SKILL.md
     prereq: Drift check workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->

# Drift Check

Compare the project's recorded templateCentral install version to the current plugin version, report convention drift, and optionally run dependency and security checks.

## Step 1 — Confirm a templateCentral project

Line 1 of the project's `AGENTS.md` must be the harness marker:

```
<!-- templateCentral: <stack>@<schema-version> -->
```

e.g. `<!-- templateCentral: nextjs@6.0.0 -->`. `@X.Y.Z` is the harness *schema floor*, not the install version — never compare it to the plugin semver; it only identifies `<stack>`.

No marker → not a templateCentral project. Exit silently.

## Step 2 — Read both versions

- **Project version**: `templatecentral_version` in the project's `.claude/harness.json`.
- **Plugin version**: `version` in `<skill-dir>/../../.claude-plugin/plugin.json` (the version SSOT).

**`.claude/harness.json` missing** → no recorded install version. Do not report drift; tell the user:

> "`.claude/harness.json` not found — this project has no recorded install version. To adopt the templateCentral harness, run `templatecentral:migrate`."

Then exit, unless the request asked for a quality check: then go to Step 7.

## Step 3 — Compare (semver `major.minor.patch`)

- Project version ≥ plugin version → conventions are current (or the installed plugin is older than the project). Skip Step 4, run Step 4b. If the project `AGENTS.md` contains `<!-- templateCentral-check-deps -->`, go to Step 5; otherwise exit silently, unless the request asked for a quality check: then go to Step 7.
- Project version < plugin version → drift. Continue.

## Step 4 — Convention drift report

Read `<skill-dir>/../../CHANGELOG.md`. Extract every entry newer than the project version that touches the detected stack, the shared harness, or skills the project uses. Also compare the project's pinned versions against the `Stack:` line in `<skill-dir>/../../.claude/rules/<stack>.md`.

Report in this shape (content comes from the changelog — never invent entries):

```
templateCentral convention drift detected

Project install version: <project version>
Current plugin version:  <plugin version>

Changes since your install (<stack>-relevant):
### <version>
- <changelog line>

Stack floors not met:
- <package>: project <x>, floor <y>

Convention updates are manual — review the above and apply what is relevant.
```

## Step 4b — Known older patterns (read-only, any version)

Run `bash "<skill-dir>/../migrate/general/defect-report.sh" <project-dir>`. It filters by file, not by version, so run it whatever Step 3 found. Show its output only when it matched something. It writes nothing and needs no login, key or network. Change project source only after the user confirms each fix; the notes are `<skill-dir>/../migrate/general/UPGRADE-NOTES.md`.

## Step 5 — Dependency drift (optional)

Ask:

> "Dependency drift check is available — it compares your declared dependencies against the latest registry versions. Run it? (y/n)"

If the user accepts, or the project `AGENTS.md` contains `<!-- templateCentral-check-deps -->`, dispatch the review utility's `update` operation (`cat "<skill-dir>/../review/SKILL.md"`). The marker skips the question and runs this step even when Step 3 found no convention drift.

## Step 6 — Security audit (optional)

Ask:

> "Security audit available — checks installed packages against advisory databases. Run it? (y/n)"

If accepted:

- **Node stacks**: `pnpm audit --audit-level=high`. Also list every entry in `.claude/dep-audit-allow.txt` and flag any whose advisory now has a fixed release or whose documented reason no longer holds; flag any `audit.ignore` / `auditConfig` in `pnpm-workspace.yaml` or `package.json` as a bypass the deps gate rejects.
- **FastAPI**: if `pip-audit --version` succeeds, run `pip-audit -r requirements.txt`; otherwise report "pip-audit not installed — security advisory check skipped". Review `.claude/dep-audit-allow.txt` the same way.

Zero findings → "No known vulnerabilities found." Otherwise list package, severity, advisory ID, and whether a fixed version exists, and recommend the review utility's `update` operation. Never auto-upgrade.

## Step 7 — Quality (optional)

Run only when the request asked for a quality check, or after Step 6. Ask first and state the cost: the run executes the project's tests with coverage plus lint, typecheck, complexity and duplication (up to 10 minutes per tool). Skip this step when the user declines.

On yes, load `cat "<skill-dir>/../migrate/general/quality-baseline.md"` and run its script with `--full`, only because the user said yes above. The script runs no project script, test or hook of its own; git reads the tree and may run filters that the user's git config defines. Its last row reports any write to the project. Print the metric table, then up to five worst offenders per category with file paths. If `docs/quality-baseline.md` exists, compare against its latest column (`after` if present, else `before`) and mark each metric that moved the wrong way. Exit 3 means no number got worse but a gate configuration file changed: show that list to the user and state what changed in each file; never call a threshold, scope or rule change neutral. Name each metric that misses the target and recommend `templatecentral:migrate` for the fix.

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

e.g. `<!-- templateCentral: nextjs@6.0.0 -->`. The `@X.Y.Z` here is the harness *schema floor*, not the install version — never compare it to the plugin semver. It only identifies `<stack>`.

No marker → not a templateCentral project. Exit silently.

## Step 2 — Read both versions

- **Project version**: `templatecentral_version` in the project's `.claude/harness.json`.
- **Plugin version**: `version` in `<skill-dir>/../../.claude-plugin/plugin.json` (the version SSOT).

**`.claude/harness.json` missing** → the project was adopted or hand-crafted, so there is no recorded install version. Do not report drift; tell the user:

> "`.claude/harness.json` not found — this project has no recorded install version. To adopt the templateCentral harness, run `templatecentral:migrate`."

Then exit.

## Step 3 — Compare (semver `major.minor.patch`)

- Project version ≥ plugin version → conventions are current (or the installed plugin is older than the project). Exit silently.
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

## Step 5 — Dependency drift (optional)

Ask:

> "Dependency drift check is available — it compares your declared dependencies against the latest registry versions. Run it? (y/n)"

If the user accepts, or the project `AGENTS.md` contains `<!-- templateCentral-check-deps -->`, dispatch the review utility's `update` operation (`cat "<skill-dir>/../review/SKILL.md"`). The escape-hatch marker forces this step even when Step 3 found no convention drift.

## Step 6 — Security audit (optional)

Ask:

> "Security audit available — checks installed packages against advisory databases. Run it? (y/n)"

If accepted:

- **Node stacks**: `pnpm audit --audit-level=high`.
- **FastAPI**: if `pip-audit --version` succeeds, run `pip-audit -r requirements.txt`; otherwise report "pip-audit not installed — security advisory check skipped".

Zero findings → "No known vulnerabilities found." Otherwise list package, severity, advisory ID, and whether a fixed version exists, and recommend the review utility's `update` operation. Never auto-upgrade.

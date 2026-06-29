<!-- ref: standards/drift-check/implementation.md
     loaded-by: standards/SKILL.md
     prereq: Drift check workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->

# Drift Check

Read the project's templateCentral version marker, compare to the current plugin version, detect drift, and optionally trigger dependency updates.

## Step 1 — Read Version Marker

Look for this comment in the project's `AGENTS.md`:

```
<!-- templateCentral: <stack>@<version> -->
```

Examples:
- `<!-- templateCentral: nextjs@1.0.0 -->`
- `<!-- templateCentral: fastapi@1.0.0 -->`

If no marker found: this project was not scaffolded by templateCentral. Exit silently — do not report anything.

## Step 2 — Read Current Plugin Version

At the plugin root (`<skill-dir>/../../`):

- `.claude-plugin/plugin.json` — the version SSOT: the `version` field is the current templateCentral version
- `.claude/rules/<stack>.md` — the stack-conventions reference: the `Stack:` line describes the current stack conventions for the detected stack

Current version = the `version` field value from `.claude-plugin/plugin.json`.

## Step 3 — Compare

The AGENTS.md line-1 marker (`@X.Y.Z`) is the harness *schema floor*, not the install version — never compare it to the plugin semver.

The install version is recorded in the project's `.claude/harness.json` → `templatecentral_version` field. Read that file now.

**If `.claude/harness.json` is missing**: the project was not installed via templateCentral (it was adopted or hand-crafted). Do not report drift. Instead, inform the user:

> "`.claude/harness.json` not found — this project has no recorded install version. To adopt the templateCentral harness, run `templatecentral:migrate`."

Then exit.

Parse both versions as semver (`major.minor.patch`):
- **Project version**: `templatecentral_version` from `.claude/harness.json`
- **Plugin version**: `version` from `<skill-dir>/../../.claude-plugin/plugin.json` (already read in Step 2)

**If project version == current plugin version**: conventions are current. Exit silently.

**If project version < current plugin version**: drift detected. Proceed to Step 4.

## Step 4 — Convention Drift Report

Read `CHANGELOG.md` at the plugin root. Extract all entries with versions newer than the project version, focusing on changes relevant to the detected stack. Also diff the project's conventions against the `Stack:` line in `.claude/rules/<stack>.md`.

Show the user:

```
templateCentral convention drift detected

Your project: nextjs@1.0.0
Current:      nextjs@1.2.0

What changed since your project was scaffolded:
### 1.2.0
- Updated proxy.ts to use better-auth session check (auth.api.getSession)
- Added error-boundary pattern to layout.tsx

### 1.1.0
- Replaced manual HTTPS agent with native fetch in axios-client.ts
- Added `output: "standalone"` to next.config.ts

Convention updates are manual — review changelog above and apply relevant changes to your project.
```

## Step 5 — Dependency Drift Check

After showing the convention report, ask the user:

> "Dependency drift check is available. This fetches current versions from npm for all packages in your package.json. Run it? (y/n)"

If user declines: skip to Step 6.

If user accepts or project AGENTS.md contains `<!-- templateCentral-check-deps -->` escape hatch: dispatch the update utility (`skills/review/update/implementation.md`).

## Step 6 — Security Audit

After Step 5 (or after Step 4 if user declined Step 5), ask:

> "Security audit available — checks installed packages against the package ecosystems' advisory databases. Run it? (y/n)"

**If user accepts:**

- **Node projects**: run `pnpm audit --audit-level=high` (or `npm audit --audit-level=high`). Report any high/critical findings. If vulnerabilities found, recommend running the review utility (update operation — `cat "<skill-dir>/../review/SKILL.md"`) to patch.
- **Python projects**: if `pip-audit` is available (`pip-audit --version` returns without error), run `pip-audit --requirement requirements.txt` and report findings; if not installed, add "pip-audit not installed — security advisory check skipped" to report.

If zero vulnerabilities: report "No known vulnerabilities found."
If findings: list package name, severity, advisory identifier, and whether a fix is available. Do not auto-upgrade — let the user decide.

If user declines: done.

## Escape Hatch

Users can trigger dependency drift check at any time without convention drift by adding this line to their project AGENTS.md:

```
<!-- templateCentral-check-deps -->
```

When this marker is present, run Step 5 regardless of convention drift status.

## Invocation

This skill is invoked automatically at session start for projects that contain the templateCentral version marker in AGENTS.md. The project AGENTS.md should contain:

```
At session start, invoke the drift-check skill.
```

## Changelog
### 1.1.0
- Fix: Step 3 now reads `templatecentral_version` from `.claude/harness.json` instead of the AGENTS.md line-1 marker. The marker is the harness schema floor (lint-enforced, deliberately pinned) and must never be compared to the plugin semver. Missing `harness.json` routes to `templatecentral:migrate` instead of reporting false drift.

### 1.0.0
- Initial plugin release
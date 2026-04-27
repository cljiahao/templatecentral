---
name: drift-check
description: Use when starting a session on a project scaffolded by templateCentral — checks convention version and optionally dependency drift
---

# Drift Check

Read the project's templateCentral version marker, compare to the current scaffold skill version, detect drift, and optionally trigger dependency updates.

## Step 1 — Read Version Marker

Look for this comment in the project's `AGENTS.md`:

```
<!-- templateCentral: <stack>@<version> -->
```

Examples:
- `<!-- templateCentral: nextjs@1.0.0 -->`
- `<!-- templateCentral: fastapi@1.0.0 -->`

If no marker found: this project was not scaffolded by templateCentral. Exit silently — do not report anything.

## Step 2 — Read Current Scaffold Skill Version

Load the scaffold skill for the detected stack and read its `version` frontmatter field:

| Marker stack | Scaffold skill |
|---|---|
| `nextjs` | `nextjs/scaffold` |
| `vite-react` | `vite-react/scaffold` |
| `fastapi` | `fastapi/scaffold` |
| `nestjs` | `nestjs/scaffold` |

Current scaffold skill version = the `version` field value.

## Step 3 — Compare

Parse both versions as semver (`major.minor.patch`).

**If project version == current skill version**: conventions are current. Exit silently.

**If project version < current skill version**: drift detected. Proceed to Step 4.

## Step 4 — Convention Drift Report

Read the scaffold skill's `## Changelog` section. Extract all entries with versions newer than the project version.

Show the user:

```
templateCentral convention drift detected

Your project: nextjs@1.0.0
Current:      nextjs@1.2.0

What changed since your project was scaffolded:
### 1.2.0
- Updated proxy.ts to use new NextAuth v5 session callback signature
- Added error-boundary pattern to layout.tsx

### 1.1.0
- Replaced manual HTTPS agent with native fetch in axios-client.ts
- Added `output: "standalone"` to next.config.ts

Convention updates are manual — review changelog above and apply relevant changes to your project.
```

## Step 5 — Dependency Drift Check

After showing the convention report, ask the user:

> "Dependency drift check is available. This fetches current versions from npm for all packages in your package.json. Run it? (y/n)"

If user declines: done.

If user accepts or project AGENTS.md contains `<!-- templateCentral-check-deps -->` escape hatch: dispatch `update-agent`.

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
### 1.0.0
- Initial plugin release

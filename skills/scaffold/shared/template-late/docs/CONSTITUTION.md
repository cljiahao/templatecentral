# CONSTITUTION.md

## 1. Purpose

This document defines the non-negotiable invariants for **__TC_PROJECT_TITLE__**.
It applies to all contributors — human and AI agent alike. When `AGENTS.md`,
templateCentral skills, or any other guidance conflicts with this document,
**this document wins**. No PR may be merged that violates these rules without
an explicit `## Human Approval Override` section in the PR description.

## 2. Architecture Invariants

[Fill in: the load-bearing architectural rules: layering, module boundaries, composition root, forbidden cross-imports]

## 3. Security Invariants

- Secrets stay out of code, git, logs and build output. Load them from environment
  variables fed by a secrets manager.
- Routes that read or change user data authenticate before running business logic.
  Add authentication (`templatecentral:add auth`) before the first such route.
- [Fill in: which mutations must write an audit log, or delete this line]

## 4. Testing Invariants

- New services must have integration tests (success, error, at least one edge case).
- New API routes must have route tests covering 200 and at least one error path, plus 401 once
  authentication exists.
- CI must stay green — no PR may be merged with failing tests.

## 5. Git & PR Invariants

- Branch from `main`. Protected branches (`main`, `uat`, `develop`) — no direct commits.
- [Fill in: PR requirements for `uat` and `main`, e.g. a filled PR template, or delete this line]

## 6. Agent Governance Rules

### Protected files — human approval required

The following files require explicit human approval, noted in the PR description under
a `## Protected File Changes` heading. Agents edit them only with that approval.

- `AGENTS.md` / `CLAUDE.md` — agent instruction files
- `docs/CONSTITUTION.md` — this document
- `.claude/settings.json` — harness wiring
- `.claude/hooks/*` — enforcement hooks
- `Dockerfile`
[Fill in: project-specific protected files, or delete this line]

### Behavioural rules

- Run the quality gate ([Fill in: the stack's quality-gate command]) before declaring any task done.
- Do not use `--no-verify` on commits; it bypasses the pre-commit hooks.
- Work on a feature branch. Do not commit directly to `main`, `uat` or `develop`.

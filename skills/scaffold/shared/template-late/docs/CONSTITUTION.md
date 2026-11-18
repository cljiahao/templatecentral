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

**Test-value rule** — the one rule for what to test; skills and `AGENTS.md` point here.

- Test behaviour that can regress. One test per distinct behaviour.
- Parametrize sibling cases (`it.each`, `pytest.mark.parametrize`) instead of copy-pasting them.
- Before adding a test, check whether an existing one already covers the behaviour; extend it.
- No tests that only restate a constant, type or re-export, exercise framework behaviour, or are mocks asserting themselves: they add no coverage or behaviour value. This never excuses skipping tests of real code paths.
- Meet the changed-line coverage gate (80%) with behaviour tests, never by excluding files or adding ignore pragmas.
- Security minimum: an authenticated route keeps one unauthenticated-rejected test. Shared auth guards are tested once, not per route.
- Scaffolded template code ships with its own tests; add tests only for code you add or change.
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

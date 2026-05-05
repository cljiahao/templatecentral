# Changelog

All notable changes to templatecentral are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [2.1.0] — 2026-05-05

### Fixed
- May 2026 accuracy, security, and compliance pass across all skills
- Next.js minimum version bumped to 16.2.4+ / 15.5.9+ (security patches)
- IM8 compliance: bcrypt cost factor, secret validation, rate limiting
- better-auth CVE minimum version enforced
- Zod v4 email error format updated
- Engines fields added to all Node scaffolds (Node ≥22)
- Scaffold verification gates aligned with AGENTS.md
- Dead-end `add-*` skills now include Validate + dispatch routing

---

## [2.0.0]

### Added
- 46-skill plugin with full `plugin.json` + `marketplace.json` manifest
- GitHub install path (`claude plugin marketplace add cljiahao/templatecentral`)
- Shared skills: `drift-check`, `full-stack-pairing`, `task-management`, `update-agent`
- Independent test workflow (Tier 0/1/2) documented in AGENTS.md
- Supply chain and reproducibility rules (pnpm lockfile, Python version pins)

### Changed
- Flat `<stack>-<skill>` directory naming convention
- All scaffolds write `AGENTS.md` + `CLAUDE.md` after verification gates pass

---

## [1.0.0]

### Added
- Initial scaffold skills for Next.js, Vite+React, FastAPI, NestJS
- `add-auth`, `add-database`, `add-test` per stack
- `shared-add-logging`, `shared-add-error-handling`, `shared-validation-patterns`

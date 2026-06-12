# Future Directions

Design seams built into templateCentral for AI collaboration patterns that are not yet activated.

## Meta-Harness

CI that validates templateCentral's own harness layer — the harness checking itself.
Seam: `[[post-harness]]` markers inside scaffold templates (`skills/scaffold/*/source-files.md`).

## Trace-Driven Skill Evolution

Capture agent traces from real scaffolding sessions to detect skill gaps, measure step completion rates, and drive data-informed skill improvements.
Seam: `[[post-harness]]` markers inside scaffold templates (`skills/scaffold/*/source-files.md`).

## Community Skill Registry

A curated registry of third-party skills that extend templateCentral stacks (e.g. Stripe, Resend, Sentry integrations) discoverable via `templatecentral:add`.
Seam: `skills/add/` directory structure supports new capability directories.

## Automated Ecosystem Refresh

Scheduled scan of framework release notes → auto-PR to update skill content and bump `audit-ecosystem-research.md` cache.
Seam: `.github/workflows/` directory; `scripts/lint-skills.sh` and `scripts/validate-manifest.sh` modular check system.

## Harness Promotion

Promote the post-harness seams in scaffolded projects from documentation stubs to active capabilities:
- Trace capture opt-in per project
- Meta-harness CI gate
- SBOM + audit automation

*None activated yet.*

---

## Roadmap

### 1. Scaffold source-files phase-splits

Each scaffold `source-files.md` exceeds the 5,000-token skill re-attach budget. Split into phases (phase-1-core.md, phase-2-auth-hooks.md, etc.) so post-compaction recovery loads only the needed phase. Tracked in memory as `project_skills_compaction_budget`.

### 2. New `templatecentral:add` capabilities under evaluation

- **background-jobs / queues** — task queues (Celery/FastAPI, BullMQ/NestJS, Next.js server actions)
- **caching (Redis)** — response + query-level caching across all stacks
- **transactional email** — Resend / Nodemailer integration with template scaffolding

### 3. `templatecentral:migrate` light-adoption simplification

The `@1.0.0` two-pass migrate flow for projects with minimal harness drift can be significantly shorter. Evaluate a fast-path that skips Phase 3–4 for projects that only need harness seeding.

### 4. NestJS tsconfig `strict: true`

Currently `noImplicitAny: false` because `strict: true` has not been validated against a full scaffold build. Enable once the `scaffold-verify` loop confirms the scaffold compiles cleanly under strict mode.

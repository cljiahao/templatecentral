# Future Directions

Design seams built into templateCentral v4.0 for AI collaboration patterns that are not yet activated.

## Meta-Harness

CI that validates templateCentral's own harness layer — the harness checking itself.
Seam: `<!-- [[post-harness:meta]] -->` in `AGENTS.md`.

## Trace-Driven Skill Evolution

Capture agent traces from real scaffolding sessions to detect skill gaps, measure step completion rates, and drive data-informed skill improvements.
Seam: disabled trace hook in `.claude/settings.json` PostToolUse hooks.

## Community Skill Registry

A curated registry of third-party skills that extend templateCentral stacks (e.g. Stripe, Resend, Sentry integrations) discoverable via `templatecentral:add`.
Seam: `skills/add/` directory structure supports new capability directories.

## Automated Ecosystem Refresh

Scheduled scan of framework release notes → auto-PR to update skill content and bump `audit-ecosystem-research.md` cache.
Seam: `.github/workflows/` directory; `scripts/lint-skills.sh` modular check system.

## v5.0 Harness Promotion

Promote the post-harness seams in scaffolded projects from documentation stubs to active capabilities:
- Trace capture opt-in per project
- Meta-harness CI gate
- SBOM + audit automation

*Seams from templateCentral v4.0. None activated in v4.0.*

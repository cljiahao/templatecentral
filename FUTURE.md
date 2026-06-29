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

> The capability × stack matrix is already complete for the current four stacks — apparent gaps (no `database`/`endpoint` for client-only Vite; no `page`/`feature`/`form` for backend stacks) are intentional boundaries, not gaps. The items below are **net-new** capabilities, not gap-fills, and are **demand-gated**: added when a real user asks, not for completeness (the same gate as new frameworks — see §5).

- **background-jobs / queues** — task queues (Celery/FastAPI, BullMQ/NestJS, Next.js server actions)
- **caching (Redis)** — response + query-level caching across all stacks
- **transactional email** — Resend / Nodemailer integration with template scaffolding

### 3. `templatecentral:migrate` light-adoption simplification

The `@1.0.0` two-pass migrate flow for projects with minimal harness drift can be significantly shorter. Evaluate a fast-path that skips Phase 3–4 for projects that only need harness seeding.

### 4. NestJS tsconfig `strict: true` — enabled, pending verification

Enabled as `strict: true` with `strictPropertyInitialization: false` (the NestJS-idiomatic config — DTO/entity classes use declaration-only properties that full `strict` would reject). Pending a `scaffold-verify` (or manual scaffold) build confirming the generated project compiles clean under strict; if it doesn't, fix the seeded source or narrow the strict flags.

### 5. New frameworks under evaluation

New frameworks are the only way to expand coverage (the matrix in §2 is already complete), but each one is a permanent maintenance cost for a solo maintainer — a third hook-runtime variant, a `.claude/rules/<stack>.md`, and ongoing version/advisory tracking. Community consensus (create-t3-app, create-next-app, Vite) favours depth over breadth; the create-t3-app maintainers explicitly rejected going framework-agnostic because the work scales poorly. So additions are **demand-gated** — added only when real users ask, not for completeness.

**Admission bar** — a framework earns a slot only if it can deliver the same promises as the current four: (1) an encodable, agreed architecture; (2) a harness with real teeth (typecheck / test / lint / secret gates); (3) maintainable currency (trackable in `ecosystem-refresh`); (4) a non-redundant niche.

| Framework | Verdict | Notes |
|---|---|---|
| **Django** | Priority 1 (if pulled) | Distinct full-stack batteries-included niche the current menu lacks; mature, well-defined gates. Caveat: Django ships much structure itself — validate the harness adds enough on top before committing. |
| **Go** | Priority 2 (optional) | Clean gates (`gofmt`, `go vet`, `go test`, `golangci-lint`). No canonical layout — use minimal official idioms (`main.go` + `go.mod`, `internal/`, `cmd/`), NOT `golang-standards/project-layout` (self-admittedly non-official) or any single app repo. |
| **Flask** | Declined | Redundant with FastAPI, which owns the type-checked-API niche; Flask survives mainly for lightweight/MVP work. |
| **Streamlit** | Declined | Prototyping / data-app tool; lacks native structure and governance, only API-level testing — contradicts the production-ready / tested / harnessed value prop. |

See `CONVENTIONS.md` §6 for the mechanical steps to add a framework once one clears the gate.

### 6. Cross-tool support (OpenCode / OpenChamber)

**Goal:** make templateCentral usable from non-Claude-Code agents — driven by a product that wraps OpenCode/OpenChamber. **Constraint: the Claude Code plugin stays the primary, non-negotiable target** (marketplace install + full hook harness). Cross-tool is strictly additive — it must never regress the Claude Code experience.

templateCentral is three layers with different portability:

| Layer | Portability | Notes |
|---|---|---|
| **Skills** (scaffold logic) | near-portable | Agent Skills open standard; OpenCode reads `.claude/skills/`, `.agents/skills/`, `~/.config/opencode/skills/`. Blocker: routers hardcode `$HOME/.claude/plugins/marketplaces/templatecentral/…` `cat` paths. |
| **Harness** | split | **Universal half** — lefthook git-hooks + gitleaks + CI gates — already tool-agnostic (fires at commit/CI time, any tool/human). **Claude-Code half** — `.claude/hooks/` + `settings.json` in-agent guards — CC-specific. |
| **Docs** (`AGENTS.md`) | universal | already read by OpenCode and most tools. |

**Design principle: push enforcement DOWN to git-hooks / CI / `AGENTS.md` (universal), keep in-agent hooks as a per-tool layer.** The more the harness lives in lefthook + CI, the more "the full thing" is automatically cross-tool.

**Phased plan (demand-gated):**
1. **Skill path-portability.** Resolve the skill base dynamically instead of hardcoding the CC plugin path, so a clone/copy loads in OpenCode (`.agents/skills/`) without edits. ⚠️ **Open design question:** a markdown skill can't easily know its own location — needs a tool-provided plugin-root variable (e.g. `${CLAUDE_PLUGIN_ROOT}` in CC, OpenCode's equivalent) or a relative-load mechanism. Must keep resolving correctly for the CC plugin. Deserves its own design pass before any router edits.
2. **Cross-tool distribution.** Publish skills to tool-agnostic registries (`agents.toml`/skills-supply, open Agent-Skills marketplaces) so they're discoverable beyond the Claude marketplace.
3. **OpenCode-native in-agent harness adapter.** Port the live guards (typecheck-on-edit, Stop test-gate, secret/prompt-injection guards, session recovery) to OpenCode's plugin/hook API. The *logic* is portable; the *wiring* (event names, config) is per-tool — a standing per-tool maintenance cost (the "breadth tax", now for tools). Build per tool that has real demand.

**What a cloned OpenCode user gets today, before any of the above:** scaffold logic (after path fix) + `AGENTS.md` conventions + the git-hook/CI enforcement — i.e. ~80% of the value, minus the in-agent live guards.

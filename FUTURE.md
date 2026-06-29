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
| **Skills** (scaffold logic) | portable ✅ | Agent Skills open standard (SKILL.md); read natively by Claude Code, OpenCode, Codex, Antigravity, Cursor, Gemini CLI, Copilot, +others. Former blocker (hardcoded `$HOME/.claude/plugins/marketplaces/…` paths) **resolved** → `<skill-dir>` placeholder, validated portable (see Phase-1 resolution below). |
| **Harness** | split | **Universal half** — lefthook git-hooks + gitleaks + CI gates — already tool-agnostic (fires at commit/CI time, any tool/human). **Claude-Code half** — `.claude/hooks/` + `settings.json` in-agent guards — CC-specific. |
| **Docs** (`AGENTS.md`) | universal | already read by OpenCode and most tools. |

**Design principle: push enforcement DOWN to git-hooks / CI / `AGENTS.md` (universal), keep in-agent hooks as a per-tool layer.** The more the harness lives in lefthook + CI, the more "the full thing" is automatically cross-tool.

**Phased plan (demand-gated):**
1. **Skill path-portability.** Resolve the skill base dynamically instead of hardcoding the CC plugin path, so a clone/copy loads in OpenCode (`.agents/skills/`) without edits. ⚠️ **Open design question:** a markdown skill can't easily know its own location — needs a tool-provided plugin-root variable (e.g. `${CLAUDE_PLUGIN_ROOT}` in CC, OpenCode's equivalent) or a relative-load mechanism. Must keep resolving correctly for the CC plugin. Deserves its own design pass before any router edits.
2. **Cross-tool distribution.** Publish skills to tool-agnostic registries (`agents.toml`/skills-supply, open Agent-Skills marketplaces) so they're discoverable beyond the Claude marketplace.
3. **OpenCode-native in-agent harness adapter.** Port the live guards (typecheck-on-edit, Stop test-gate, secret/prompt-injection guards, session recovery) to OpenCode's plugin/hook API. The *logic* is portable; the *wiring* (event names, config) is per-tool — a standing per-tool maintenance cost (the "breadth tax", now for tools). Build per tool that has real demand.

**What a cloned OpenCode user gets today, before any of the above:** scaffold logic (after path fix) + `AGENTS.md` conventions + the git-hook/CI enforcement — i.e. ~80% of the value, minus the in-agent live guards.

#### Phase 1 spike findings (2026-06-29) — the path swap is NOT a clean win

Hands-on testing (invoking the installed scaffold skill + probing) settled the "open design question" above, and not in the convenient direction:

- **`${CLAUDE_SKILL_DIR}` does NOT work for our loader.** It is **empty in agent-run bash** — CC only populates it for `!`-prefixed *bash-injection* commands, not the agent-run ```` ```bash cat ```` blocks templateCentral uses. A full 78-file conversion to it was implemented, **failed the live probe (`CLAUDE_SKILL_DIR=[]`, cat → "No such file"), and was reverted.** Do not revisit it.
- **`${CLAUDE_PLUGIN_ROOT}` also doesn't expand in skill markdown** (known CC bug).
- **The current hardcoded `marketplaces/` path actually resolves in CC** — so CC is *not* broken today. But it has a separate latent bug: the running skill is `cache/…/<active-version>` while the hardcoded path points at `marketplaces/…` (the *latest* marketplace clone), so an older installed version can load newer reference files (version drift).
- **base-dir-from-invocation works** (CC shows "Base directory for this skill: …"; catting that absolute path resolves ✓) — but it is **model-dependent** (the agent must substitute the shown path) and a large prose rewrite.
- **OpenCode's bundled-file resolution is undocumented** — its skills docs don't say whether it sets a skill-dir var, resolves relative reads against the skill dir, or shows the dir. **Needs hands-on OpenCode testing**, not assumption.

#### Phase 1 OpenCode test findings (2026-06-29) — `<skill-dir>` has a confirmed structural basis in OpenCode

Tested against the user's own OpenCode (binary v1.17.11) with a marker skill in `.opencode/skills/sdtest/`, using the no-auth `opencode debug skill` introspection command:

- **OpenCode tracks each skill's full `location`.** `opencode debug skill` returns per skill: `name`, `description`, `content`, and **`location`** = absolute path to that skill's `SKILL.md`. The skill's base directory is `dirname(location)`. This is the exact structural equivalent of Claude Code's "Base directory for this skill" line — OpenCode *has* the dir and could surface it to the agent, which is the prerequisite for `<skill-dir>` to resolve there.
- **Confirmed OpenCode skill discovery layout** (from its built-in "customize opencode" skill): project `.opencode/skill(s)/<name>/SKILL.md`, global `~/.config/opencode/skill(s)/<name>/SKILL.md`, auto-loaded external `~/.claude/skills/<name>/SKILL.md` + `~/.agents/skills/<name>/SKILL.md`, plus `skills.paths` (scanned recursively for `**/SKILL.md`) and `skills.urls` in `opencode.json`. So templateCentral's `.claude/skills/`-seeded skills are auto-discovered by OpenCode with no extra config.
- **Remaining 5% (auth-gated):** whether OpenCode's `skill` *tool* surfaces `location` to the **agent** at invocation (vs only internally / to `debug`). CC does (validated end-to-end). To confirm for OpenCode needs one authenticated `opencode run` with a marker skill (requires the user's `GENCENTRAL_API_KEY`) — or reading `packages/core/src/plugin/skill.ts` in the OpenCode source.
- **Fallback if the tool does NOT surface it:** a tiny templateCentral OpenCode plugin (the same pattern as the user's existing `.opencode/plugins/superpowers.js`, which already registers skills via `config.skills.paths`) can inject the resolved skill dir. Low cost, known pattern.

**Net:** `<skill-dir>` is CC-validated today and structurally supportable in OpenCode (OpenCode knows the dir). The conversion already shipped is the right portable form for both — no rework needed; only the final agent-visibility confirmation (auth run or source read) remains before claiming full OpenCode parity.

#### Phase 1 RESOLVED (2026-06-29) — `<skill-dir>` is portable across all four target tools; no rework needed

Closed the OpenCode question from source and grounded the rest in official docs (web research, 2026-06-29). Both standards templateCentral builds on are now cross-vendor:

- **AGENTS.md is a Linux Foundation standard** — stewarded by the **Agentic AI Foundation** (OpenAI donated AGENTS.md, Anthropic donated MCP, Block donated goose; co-founders incl. Google/Microsoft/AWS). 60,000+ projects. Read natively by Codex (global `~/.codex/` → repo-root → nested, closest-wins, 32 KiB cap), Antigravity (after GEMINI.md), and Claude Code (`CLAUDE.md = @AGENTS.md`). templateCentral's instruction layer is portable **unchanged**.
- **SKILL.md / Agent Skills (agentskills.io) is an open standard** read by Claude Code, OpenCode, Codex (shipped 2025-12-19), Antigravity, Cursor, Gemini CLI, Copilot, Windsurf, +others. Directory-based: `SKILL.md` + optional `scripts/`/`references/`/`assets/`. Convention: reference bundled files by **relative path from the skill root, one level deep**.

**Does the agent get the skill's base directory? (the `<skill-dir>` linchpin) — YES on all four:**

| Tool | Mechanism (source) | `<skill-dir>` works |
|---|---|---|
| **Claude Code** (primary) | Prints `Base directory for this skill: <abs>` at invocation | ✅ validated end-to-end |
| **OpenCode** | `skill` tool (`packages/core/src/tool/skill.ts`, `toModelOutput`) appends verbatim `Base directory for this skill: <abs>` + `Relative paths … are relative to this base directory` | ✅ proven from source (`dev` @ 6d9539f) |
| **Codex** | Injects each skill's path as `(file: /abs/.../SKILL.md)`; agent constructs bundled paths from it | ✅ official (developers.openai.com/codex/skills) |
| **Antigravity** | Directory-based skill; agent has skill-dir awareness, relative paths resolve from skill root | ✅ official codelab examples (`scripts/x.py`, `resources/x.txt`) |

**Why templateCentral uses `<skill-dir>/…` (abs prefix) and not bare relative paths:** loads go through agent-run ```bash``` `cat`, which resolves relative paths against the **project cwd**, not the skill dir. So the agent must prepend the absolute base dir the tool surfaces. `<skill-dir>` is exactly that — proven in CC + OpenCode, compatible with Codex/Antigravity path exposure. **The shipped conversion is correct for all four; no fallback plugin needed.**

**What is portable today vs. what needs a per-tool adapter (matches the layer split above):**
- **Portable now (zero/near-zero work):** all `SKILL.md` scaffold logic + bundled reference files; the `AGENTS.md` instruction/routing layer; MCP configs (CC, OpenCode, Codex all speak MCP); the git-hook/CI half of the harness (lefthook + gitleaks + CI — fires for any tool/human).
- **Per-tool adapter (the "breadth tax", confined to the harness edge):** the in-agent live guards (`.claude/hooks/` + `settings.json`) → Codex has a close hook model (`SessionStart`/`PreToolUse`/`PostToolUse`/`PreCompact`/`PostCompact`/`Stop`, command-type, GA 2026-05-14) so the lint/compact hooks re-implement cleanly; OpenCode needs its plugin API (Phase 3, #17). Project slash commands (`/tc-audit`, `/tc-write-skill`) → re-expose as `$name` skills. Plugin-marketplace packaging → distribute skills individually / via registries (Phase 2, #16). Community converter `acplugin` mechanizes most of the delta (hooks remain a manual port).

**Bottom line:** Claude Code stays the primary, fully-featured target (plugin + complete hook harness). A clone dropped into OpenCode / Codex / Antigravity today gets the scaffold logic + AGENTS.md conventions + git-hook/CI enforcement — ~80% of the value — with no edits, because both underlying standards are cross-vendor and the `<skill-dir>` form resolves in each. The remaining 20% (in-agent live guards) is the per-tool adapter work tracked in #16/#17, built per tool that has real demand.

**Nuances confirmed (do not relitigate):**
- **`${CLAUDE_SKILL_DIR}` is real but wrong for us.** It IS officially documented — but only for *bash-injection* commands (the `!`-prefix / frontmatter-allowed bash), where CC substitutes it. In the agent-run ```` ```bash cat ```` blocks templateCentral uses it is **empty** (matches the Phase-1 spike). Generic `$SKILL_DIR` was closed "not planned" (anthropics/claude-code#12541); `${CLAUDE_PLUGIN_ROOT}` does not expand in markdown bodies (#9354). The agent-substituted `<skill-dir>` placeholder sidesteps all three — keep it.
- **The portable convention is relative-from-skill-root for files the agent *reads*; it breaks only when *shelling out* to bundled scripts** (shell CWD = the user's project, not the skill dir). templateCentral loads reference files via `cat "<skill-dir>/…"` — an **absolute** prefix the agent builds from the surfaced base dir — so it never depends on shell CWD and is safe across all four tools. (If a future skill needs to *run* a bundled script portably, that one path is the only spot needing per-tool care.)
- **Claude Code does NOT natively read AGENTS.md** as of 2026-06 (anthropics/claude-code#34235 open). `CLAUDE.md = @AGENTS.md` is the documented workaround — templateCentral already does exactly this, so the AGENTS.md layer loads on CC and is read natively everywhere else.

**Phase-2 lever (#16) — compile step:** if true multi-tool *emission* becomes a goal (vs. relying on each tool reading `.claude/skills/` directly), `rulesync` (github.com/dyoshikawa/rulesync) compiles a single source into per-tool configs (Cursor, Claude Code, Copilot, Gemini/Antigravity, Zed) and already treats skills as a transformable feature. Community converter `acplugin` (CC plugin → Codex/Cursor) covers most of the harness delta but only warns on hooks. Evaluate when demand is real — premature for a solo maintainer now.

**Revised stance:** the swap trades CC's *working* loader for a *model-dependent* one to gain portability that can't yet be validated on OpenCode — backwards from "CC is primary." So Phase 1 is **not** a simple find-replace. Recommended re-scope: (a) leave CC's loader working; optionally fix the version-drift separately; (b) treat OpenCode portability as its own effort that **starts with hands-on OpenCode testing** of how it resolves bundled files, then chooses a mechanism (relative-read, base-dir, or a build-step variant) proven against *both* tools before any mass conversion.

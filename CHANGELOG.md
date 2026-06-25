# Changelog

All notable changes to templatecentral are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [5.2.0] — 2026-06-25

### Added

- **Seeded git-hook layer (lefthook).** Every scaffold now seeds `lefthook.yml`, `.lefthook/commit-msg.sh`, and `.gitleaks.toml` — a commit-time enforcement layer that runs for every committer (agent *or* human), not just inside Claude Code. Pre-commit: prettier+eslint (TS) / ruff (FastAPI) on staged files + `tsc`/`pyright` typecheck + `gitleaks protect --staged` secret scan; commit-msg: Conventional Commits; pre-push: the quality gate. Chose **lefthook over Husky** because it is a single Go binary that runs in both the TS stacks and the Python (FastAPI) stack (Husky needs a Node runtime). Hard-local; coverage / changed-line gates land in the CI workflow (next increment). The new files are drift-tracked in `harness.json` and gated by `protect-files.sh`. Adopted from a matured downstream project's DevSecOps setup, re-expressed in lefthook for polyglot support.
- **Seeded CI quality gates (GitHub Actions).** A seeded `.github/workflows/ci.yml` adds the hard-gate half of the quality story: changed-line coverage via `diff-cover` (≥80% on the diff — one tool across stacks, reading the Cobertura XML both Vitest and pytest-cov emit), a lockfile-in-sync check (`pnpm install --frozen-lockfile`), a full-history gitleaks scan, and a changelog-touched gate (`src/` changed ⇒ `CHANGELOG.md` must change, bypass via a `skip-changelog` label). Version pinning stays **caret-floors + committed lockfile** (not reversed) — the frozen-install check covers reproducibility without an anti-caret ban.
- **Seeded harness integrity verifier (`.claude/verify-harness.sh` + `regen-harness.sh`).** Closes the loop on `harness.json`, which recorded `origin_hash`es that nothing checked. A portable bash sensor (SHA-256; jq/node/python3 fallback so it runs on every stack — unlike a Node-only `.mjs`) recomputes the **enforcement-layer** hashes (hooks, `settings.json`, lefthook, gitleaks, CI) and fails CI / pre-push on drift; living docs (`AGENTS.md`, skills) are excluded so they evolve without false positives. The baseline is re-blessed only by a **human** running `regen-harness.sh` (an agent regenerating it would mask drift — explicit-baseline best practice). `harness.json` and the verifier scripts were added to `protect-files.sh`'s approval list so the baseline can't be silently rewritten. Validated end-to-end (OK / tamper→drift / missing / living-doc-ignored / regen).

### Security

- **Next.js auth: optimistic-proxy + authoritative-layout model.** `add (auth)`'s `proxy.ts` called `auth.api.getSession()` directly in the Edge-runtime proxy (unreliable — it pulls in Node-only DB/crypto code) and the protected `DashboardLayout` did no server-side check, so route protection relied entirely on the proxy. The proxy now does an Edge-safe optimistic `getSessionCookie()` check for routing/redirects, and the layout does the authoritative `auth.api.getSession()` validation (redirect on failure) — matching better-auth's documented Next.js pattern.
- **Harness: `protect-files.sh` now actually gates governance files.** The hook "warned" via `exit 1` on writes to `AGENTS.md`/`CLAUDE.md`/`.claude/settings.json`/`.claude/hooks/*`/`Dockerfile`, but `exit 1` is non-blocking on PreToolUse — the edit went through and the message never reached the model. It now emits a `permissionDecision: "ask"` JSON envelope so Claude Code prompts for human approval before the write. Affects every newly scaffolded/migrated project.
- **`block-no-verify.sh` now blocks `git checkout`/`git restore` on guard-layer files** (`.claude/`, `lefthook.yml`, `.github/`, `AGENTS.md`, `CLAUDE.md`, `docs/CONSTITUTION.md`). Previously an agent could silently wipe enforcement config by discarding working-tree changes to it — a real data-loss class observed in a downstream project.

### Fixed

Repo-wide skill-content cleanup (audit + smell/debt/dedupe pass). 37 reference files touched, net −105 lines.

- **Security drift reconciled across stacks.** The Vite stack shipped a *weaker* `fileUploadSchema` (missing the extension whitelist and `../`/decode path-traversal checks) and a logging redaction list that silently omitted `address` — both restored to the canonical in `standards/validation-patterns/patterns.md`. `passwordSchema` had diverged; all stacks now share the strongest superset (min-12 + lower + upper + number).
- **Correctness fixes.** Next.js pagination truncated snake_case sort fields (`desc_created_at`) — fixed to match the NestJS sibling. FastAPI Pydantic v2 `@field_validator` missing `@classmethod`. FastAPI `list_users` had a return annotation that contradicted its own "never return raw ORM objects" note (two files).
- **Info-disclosure hygiene.** Removed raw `ValidationError` interpolation (its `str()` echoes submitted input) from FastAPI validation examples.
- **Type-safety regressions** removed: `as any` in NestJS logging, untyped `@Req()`, untyped `JSON.parse`, dropped Drizzle schema generic, untyped axios responses.
- **Deduplication.** Collapsed a ~110-line verbatim auth section in `sqlalchemy-iam.md` to a pointer; removed duplicate `## Validate` blocks (4 files), duplicate test helpers (2 files), and a duplicated AGENTS.md routing row; reconciled drifted IAM-token error handling.
- **Hygiene:** `typing.Sequence` → `collections.abc.Sequence` (3 sites), Ruff `B904 from None`, `==`→`===` in TS examples, deprecated unused exports/params removed, 500-message casing aligned, log `pagehide` flush added, mixed camelCase serialization aliases fixed, missing imports added, `mutation-testing` CI Node 22 → 24.
- **Anti-drift:** the seeded `FUTURE.md` credit no longer hardcodes a version string (was "v4.0"), so it cannot re-stale.
- **UI consistency:** raw Tailwind colors in the generated scaffold UI (`text-red-*`, `bg-white`, `bg-green-*`, `bg-black`, etc.) replaced with shadcn theme tokens so generated components adapt to dark mode; reconciled the drifted `error-log-handler.ts` parameter name across the Next.js/Vite scaffolds (kept as separate per-stack files, not merged).

---

## [5.1.0] — 2026-06-15

Marketplace-readiness release. Separates repo-maintenance tooling from the shipped plugin surface so installed projects carry only end-user skills.

### Changed

- **`audit` and `write-skill` are now repo-internal contributor skills, not shipped plugin skills.** Both moved from `skills/` to `.claude/skills/` and were renamed to project skills `/tc-audit` and `/tc-write-skill`. They are available when you clone and open this repo, but are no longer installed into end-user projects (the marketplace ships only the plugin's `skills/` directory). Rationale: their purpose is maintaining templateCentral itself (`lint-skills.sh`, CONVENTIONS.md, the skill tree) — they were never meaningful for a scaffolded app, yet every install carried them and their routing rows.
- **Shipped skill count is now 8** (4 user-invocable: `scaffold`, `add`, `migrate`, `standards` + 4 de-registered cat-path utilities: `build`, `test`, `review`, `cleanup`). README and `marketplace.json` counts updated from 10.

### Fixed

- **Scaffolded `AGENTS.md` no longer advertises `templatecentral:audit`.** The `| full ecosystem + accuracy audit |` routing row was embedded in all four scaffold `source-files.md` templates and the migrate routing table, pointing end-user projects at a skill that only ever audited the templateCentral repo. Removed from all five sites.
- **Lint guard updated**: `templatecentral:audit` / `:write-skill` added to the ghost-name ban so a plugin-namespaced reference to either inside shipped `skills/` now fails the gate (they resolve only as `/tc-audit` / `/tc-write-skill` project skills).

### Repo

- **Release history tagged**: annotated git tags `v1.0.0` … `v5.1.0` created retroactively, each pinned to the commit that introduced that `plugin.json` version.

---

## [5.0.1] — 2026-06-12

### Fixed

- **`.agents` symlink must never be committed** — all four scaffold `.gitignore` templates now list `.agents` (with the why), and the harness kit Step F + migrate Step 4f-2 instruct verifying/adding the entry. A git-tracked symlink breaks Windows CI build agents (e.g. "Unable to load symbolic/hard linked file" on Azure DevOps hosted runners); the symlink is per-machine convenience and should be recreated locally. Lesson adopted from the appCentral reference harness, which documented the failure in production CI.

---

## [5.0.0] — 2026-06-12

Major release. Includes the changes previously staged (unpublished) as 4.6.0.

### BREAKING

- **Add-capability consolidation**: `endpoint`/`api-route`/`module` merged into `endpoint` (per-stack files); `component` folded into `feature`; `mutation` renamed `mutation-testing`. Aliases for all old names remain in `add/SKILL.md` routing — existing invocations continue to work.
- **Utility skills (build/test/review/cleanup) are now cat-path only**: `templatecentral:build`, `templatecentral:test`, `templatecentral:review`, `templatecentral:cleanup` no longer resolve as registered skills — the OLD form (registered skill invocation) is banned; use the cat-path contract instead: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/implementation.md"`. All references swept across skill files.
- **Harness schema floor bumped 4.0.0 → 5.0.0**: AGENTS.md markers and `templatecentral:migrate` now target 5.0.0. `templatecentral:migrate` upgrades 4.x projects and converts flat seeded skills (`<name>.md`) to `<name>/SKILL.md` directory form.

### Added

- **Loop engineering**: scheduled `ecosystem-refresh` and `scaffold-verify` GitHub Actions loops; loop-engineering research topic added as audit Step 0b to surface harness-engineering practice from community sources.
- **`add (logging)` for Vite+React**: logging capability extended to the fourth stack (was FastAPI/NestJS/Next.js only).
- **Audit conventions checks C1–C6 folded into lint (C1–C4 as new checks; C5 was a duplicate of C3; C6 merged into the existing jurisdiction check)**: ghost-utility-name ban and version-stamp ban (`STRICT_DOC_SYNC`) now enforced by lint; `check_harness_version_matches_plugin` catches straggler version sites.
- **`validate-manifest` extended checks**: plugin extended fields, marketplace consistency, CHANGELOG heading presence — all validated on every CI run.
- **Shellcheck CI job**: `shellcheck scripts/*.sh` + `bash -n` syntax check added to `validate-skills.yml`.
- **Shared migrate cores**: `drizzle-to-kysely.md` shared migration guide; backend-extraction `common.md` shared core for FastAPI + NestJS extraction paths.
- **`FUTURE.md` roadmap**: approved harness-kit extraction (Option A) documented as the v5.x roadmap.
- **Shared harness kit** — the ~560-line harness kit (settings.json, 8 hook scripts, CONSTITUTION/FUTURE templates, harness steps) now lives once in `skills/scaffold/shared/harness-kit.md` with a per-stack delta table; all 4 scaffolds + migrate load it (removes ~1,832 duplicated lines and the copy-drift bug class).
- **`templatecentral:audit` 2.6.0 — community-consensus harness research** (Step 0b): each audit now scans Anthropic official guidance plus community sources (claude-code GitHub discussions, practitioner write-ups) for harness-engineering practice, graded `RECOMMENDED` (official) / `CONSENSUS` (≥3 sources) / `EMERGING` (track only). RECOMMENDED/CONSENSUS gaps become targeted Step 3H checks. Cache template gained a matching section; first scan cached 2026-06-12.
- **Lint: `check_seeded_skill_paths_are_directories`** — fails on any scaffold/migrate instruction seeding a flat `.claude/skills/<name>.md`; `check_scaffold_seeds_complete_harness` now positively requires `-verify/SKILL.md` directory form and the `stop_hook_active` guard in every scaffold.
- `skills/write-skill/implementation.md` — authoring checklist moved out of the registered SKILL.md body (CONVENTIONS §3 compliance); SKILL.md is now detection + cat only.

### Fixed

- **Execution-verified all four scaffolds end-to-end; fixed the template bugs the runs surfaced** (NestJS: missing eslint-config-prettier peer + @scarf/scarf allowBuilds + tsconfig missing test/** include; FastAPI: pyright-clean templates — ConfigDict explicit expansion, `_send(message: Message)` typing, setattr for logging handler, import order — and requirements-dev.txt wired into install; Vite: Slot misuse, CSS @import order; all stacks: format-before-first-check note).
- **Execution-verified the Next.js scaffold end-to-end; fixed 4 template bugs it surfaced** (missing `LinkItem` re-export; FlatCompat ESLint config broken on current eslint-config-next — replaced with native flat imports; hook scripts excluded from app ESLint; Prettier singleQuote aligned with template sources) plus pnpm `allowBuilds` for sharp/unrs-resolver.
- **`pre-guard.sh` stdin key bug**: was reading the wrong JSON keys (silent no-op); `.env.example` exemption also corrected.
- **Drift-check false positive**: drift-check Step 2 was comparing the schema-floor marker against plugin semver, causing a false drift on every fresh project — now reads `harness.json templatecentral_version`.
- **Lint weak checks**: PCRE portability, unscoped version pins, zod message-key, seeded-skills awk (dead on BSD awk) — all hardened.
- **Scaffold dead code removed**: FastAPI Django/Flask branches, unused `DirectoryManager` utils, duplicate `verify.sh`, stale changelog block.
- **Dead "Full migration" migrate branch removed** from `templatecentral:migrate`.
- **CHANGELOG duplicate 4.5.0 headings merged**.
- **LICENSE year** corrected.
- **`FUTURE.md` seam pointers** corrected to current skill paths.
- **Docs made version-stamp-free**: all prose version stamps removed from README, EXAMPLES, CONTRIBUTING, FUTURE, SECURITY; `STRICT_DOC_SYNC=1` now hard-fails in CI.

### Fixed (from 4.6.0 staging — harness, doc-verified against official Claude Code docs)

- **Seeded project skills are now directories** (`.claude/skills/<name>/SKILL.md`) in all 4 scaffolds + migrate Phase 4. Flat `.claude/skills/<name>.md` files are silently ignored by Claude Code — every previously scaffolded project's `*-verify` skill never loaded. harness.json templates and hash commands updated to match.
- **Skill scoping order corrected** (root AGENTS.md + audit Step 3H): per current official docs, user (personal) skills override project skills on name collision — the previous claim was reversed. Plugin namespacing unaffected.
- Secrets defense-in-depth: FastAPI `.dockerignore`/`.gitignore`/`permissions.deny` now cover `src/.env` (was root-anchored — secrets were baked into Docker images and agent-readable); skills now ask the user to edit `.env` files instead of instructing hook-blocked agent edits.
- `skills/scaffold/fastapi/source-files.md`: removed duplicate `strict-transport-security` entry in `_SECURITY_HEADERS` — scaffolded FastAPI apps were emitting the HSTS header twice.
- `.claude/rules/nextjs.md`: pinned Next.js to `≥16.2.6` (16.2.5 is insecure for Turbopack deployments — App Router prefetch auth-bypass and WebSocket SSRF advisories).

### Fixed (from 4.6.0 staging — stacks)

- **FastAPI**: validation errors no longer echo submitted input (422 bodies/logs); `exc.headers` preserved (WWW-Authenticate, Retry-After); Beanie guide rewritten onto PyMongo async (`AsyncMongoClient` — the previously shown Motor class does not exist); pymongo floor ≥4.13; ForwardedHostMiddleware validates the peer against TRUST_PROXY before honoring X-Forwarded-Host; password fields bounded (`max_length=128`).
- **NestJS**: auth throttler fixed — global 3-req/15-min guard would have rate-limited the entire API; now a sane global default with `@Throttle` on login/register only. `ZodValidationException` handled in the exception filter (400 + fieldErrors; serialization failures log-and-genericize as 500). `@/` alias imports converted to relative (scaffold defines no paths mapping). PaginationService registration + `createZodDto` usage corrected. Swagger gate keys off `ENVIRONMENT` consistently.
- **Next.js**: scaffold now defines `src/lib/constants/routes.ts` (`PAGE_ROUTES`/`API_ROUTES`) — previously every fresh scaffold failed its own build gate. Auth rate-limit example rewritten: keyed on the right-most untrusted X-Forwarded-For hop only when TRUST_PROXY is set, fails closed otherwise, placed before the public-route short-circuit (was unreachable dead code), `request.ip` removed (gone in Next 15+). TRUST_PROXY unified to a hop-count convention across scaffold/auth/request-origin. `__dirname`-in-ESM migration runners fixed. `@vitest/coverage-v8` added (pre-push coverage run failed without it).
- **Vite + React**: validation-patterns Pattern 1 rewritten to the real `CustomFormField` API (previous example didn't typecheck); password schema (min 12) added; nested code fences fixed (template extraction corrupted); `.dockerignore` trimmed 236 → ~50 relevant lines; auth/feature services now Zod-validate responses; test command table matches actual scaffold scripts.
- **Cross-stack**: full-stack-pairing proxied to an `/api` prefix neither backend serves (Next rewrite destination + Vite proxy rewrite fixed); drift-check Step 2 rewired from a nonexistent `version` frontmatter to the real SSOT (plugin.json + rules files); backend-extraction guides no longer drop uncommitted work in the snapshot step and gained an auth-rewiring step (better-auth client must be replaced with JWT-endpoint calls); review/update uses `pnpm outdated`/`pip list --outdated` instead of per-package WebFetch; ai-security tier mapping covers all of LLM01–LLM10.

### Corrected (ecosystem cache)

- nginx current stable is 1.30.2 (1.30.x line) — prior cache said 1.28.3; the Vite Dockerfile pin was correct all along.
- better-auth Drizzle adapter is a separate package (`@better-auth/drizzle-adapter`); stateless no-database sessions confirmed real.

### Known

- NestJS scaffold tsconfig has `noImplicitAny: false` while the seeded AGENTS.md promises "no `any`" — enabling `strict: true` is deferred pending a scaffold build test.

---

## [4.5.0] — 2026-06-05/06

### Added (2026-06-06 — appcentral reference harness improvements)

- **`stop_hook_active` re-entry guard** (all 4 stacks, `stop-checks.sh`): reads `stop_hook_active` from the Stop hook's stdin JSON and exits 0 immediately if true — prevents the Stop gate from triggering an infinite re-entry loop when Claude re-runs after a blocking exit 2. Appcentral uses this pattern; templateCentral now exceeds it by checking via the guaranteed-present runtime (Node for TS, python3 for FastAPI).
- **Tightened injection patterns** (`user-prompt-guard.js`/`.py`, all 4 stacks): removed `'you are now a '` (false-positive on "you are now a reviewer") and `'pretend you are'` (false-positive on "pretend you are a user logging in"); replaced with specific jailbreak variants: `'you are now a different ai'`, `'you are no longer bound'`, `'pretend you are not bound'`, `'pretend you have no restrictions'`, `'act as if you have no restrictions'`, `'developer mode enabled'`. Lower false-positive rate, same or higher true-positive coverage.
- **`docs/CONSTITUTION.md` scaffold** (all 4 stacks): seeds a generic binding-invariants document template with placeholders for architecture, security, testing, git, and agent-governance rules. `session-context.sh` now re-injects it on every SessionStart if present — project-specific invariants survive compaction. `protect-files.sh` warns on edits. Pattern adopted from appcentral (where it is the single source of truth for what overrides all other guidance).

### Added (2026-06-05)

### Added

- `skills/audit/implementation.md` (v2.5.0): new **Step 7 — Documentation sync**. Every audit now keeps markdown and version markers accurate via two tracks — structural markers auto-update to match `plugin.json`; narrative docs (README, EXAMPLES, FUTURE, CONTRIBUTING, SECURITY) are checked and flagged with drafted fixes for approval.
- `scripts/lint-skills.sh`: `check_harness_version_matches_plugin` — harness.json `templatecentral_version` in scaffold/migrate templates must equal `plugin.json`. Introduced `HARNESS_SCHEMA_VERSION` constant.
- `scripts/lint-skills.sh`: `check_agents_marker_not_drifted_to_semver` — the AGENTS.md `@X.Y.Z` line-1 marker is a migration schema floor; guarded against drifting above `HARNESS_SCHEMA_VERSION` (which would break `migrate` Phase 0).
- `scripts/validate-manifest.sh`: new **DOC SYNC** section — README version badge, repo `.claude/harness.json` `templatecentral_version`, and repo `AGENTS.md` marker all validated against `plugin.json`.

### Added (multi-agent audit — scaffolding completeness)

- **Verbatim `package.json` for all 3 TS stacks** (`config-files.md`) — previously referenced a non-existent "Part A / Generation Conventions" template, so the build/test gate's scripts (`build`, `check`, `test`, `prepare`, etc.) were unresolvable and agents had to invent the manifest. Deps enumerated from each stack's import surface; versions web-verified to current stable (June 2026). The dangling references in `source-files.md` now point to the verbatim files.
- **`eslint.config.mjs` for Next.js** — Next 16 removed `next lint`; the scaffold shipped no flat config, so `pnpm check`'s lint step would fail. Added a `FlatCompat`-based config (+ `@eslint/eslintrc` dep) extending `next/core-web-vitals` + `next/typescript`.

### Changed (audit — versions, guards, docs)

- `.claude/rules/fastapi.md` + cache: **Starlette floor corrected to ≥1.0.1** (BadHost fix actually landed in 1.0.1, not 1.1.0; current stable 1.2.1) — web-verified, supersedes the cache.
- `.claude/rules/nextjs.md` + `vite-react.md`: added **React ≥19.2.7** floor (RSC DoS advisory fix; 19.2.6 had a Server-Actions regression). Scaffold package.json pins bumped to `^19.2.7`.
- **ESLint pinned to `^9` across all 3 TS stacks** (package.json `eslint` + `@eslint/js`). Web-verified rationale: `eslint-config-next 16` (nextjs) and `eslint-plugin-react-hooks 7` (vite) do not support ESLint 10 — its peer range caps at `^9`; ESLint 10 would break `pnpm install` under strict mode. NestJS aligned to `^9` for cross-stack consistency (its plugins do support 10). `globals` left at its current major (it is not tied to the ESLint version).
- `block-no-verify.sh` (all stacks): `rm -rf` guard now catches **split short flags** (`-r -f`), long-form (`--recursive --force`), and more high-value paths (`test`, `.husky`, `.git`); functionally re-tested.
- TS `stop-checks.sh`: added `command -v pnpm` guard so a missing pnpm degrades gracefully instead of hard-blocking the turn.
- `skills/add/ai-security/implementation.md`: ASI04 retitled to the official **"Agentic Supply Chain Vulnerabilities"**; LLM01 now frames denylist pattern-matching as a first layer, with the structural controls (role separation, least-agency, output validation) called out as load-bearing.
- `EXAMPLES.md`: refreshed the stale 5-event harness description to the current 7-event kit; removed the incorrect "better-auth ships in base Next.js" claim (it is added via `add (auth)`).
- `skills/scaffold/fastapi/config-files.md`: added `asyncio_mode = "auto"` to the pytest config (pytest-asyncio was installed but unconfigured).
- Drizzle pin references bumped to `v1.0.0-rc.3`.

### Fixed (multi-agent audit — schema correctness, verified against official Claude Code hooks docs)

- **Removed `continueOnBlock`** from every PostToolUse handler (4 scaffolds + 2 migrate templates) and from the audit checklist that wrongly verified it — the field does not exist in the hooks schema.
- **Removed the invalid piped `if`** (`"Edit(*.ts|*.tsx)|Write(*.ts|*.tsx)"`) — the `if` field holds exactly one permission rule. PostToolUse now filters to source-file edits **in-script** instead.
- **Post-compaction recovery now works:** replaced the inert PreCompact/PostCompact re-injection (PostCompact is observability-only and cannot inject context) with a **SessionStart** hook (`matcher: startup|resume|compact`) that re-injects routing context + universal invariants via stdout. New script `session-context.sh`.
- **FastAPI hooks are now venv-aware:** `post-edit-typecheck.sh`, `stop-checks.sh`, `subagent-stop.sh` activate `.venv` (hooks spawn a fresh shell that doesn't inherit it) and no-op gracefully if pyright/pytest is absent — previously the type gate silently no-opped (fail-open) and the test/subagent gates hard-blocked spuriously.
- **Broadened `permissions.deny`** to cover `.env.development`/`.dev`/`.uat`/`.test` (the write-guard blocked all `.env*` but the read-guard had gaps); `.env.example`/`.env.default` remain readable.
- Event set is now 7 (SessionStart replaces PreCompact+PostCompact); lint `check_scaffold_seeds_complete_harness` updated accordingly.

### Security

- **Full harness parity — seeded `.claude/hooks/` script kit (was inline `args[]`).** All 4 scaffolds + both migrate templates now seed a complete 7-event hook kit as self-contained scripts, matching the reference production harness:
  - **PreToolUse** — `protect-files.sh` (block `.env*`/CI/cert writes, warn on governance files) + `block-no-verify.sh` (block `--no-verify`, **direct commits/force-push to protected branches, `rm -rf` on source dirs**).
  - **UserPromptSubmit** — `user-prompt-guard.{js,py}`: injection patterns (OWASP LLM01) **plus credential-leak detection** (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs).
  - **PostToolUse** — filtered to source-file edits in-script (no `if` field, no `continueOnBlock` — neither does what was intended; verified against CC docs).
  - **PostToolUseFailure** (new), **SubagentStop** type-gate (new), **SessionStart** context re-injection (replaces the inert PostCompact re-inject).
  - **Stop** test gate.
  - JSON parsing uses the runtime guaranteed present per stack (Node for TS, python3 for FastAPI) so guards **fail safe**, not open.
  - Every guard functionally tested (block/allow correctness); `check_scaffold_seeds_complete_harness` enforces all 7 events + `permissions.deny` + the 8 hook scripts across every template.
- **`permissions.deny` Read-block for secrets (defense-in-depth).** All 4 scaffolds + both migrate `settings.json` templates now deny `Read(.env)`, `Read(.env.local)`, `Read(.env.*.local)`, `Read(.env.production*)`, `Read(.env.staging*)`, and `Read(./secrets/**)`. Previously the harness blocked *writing* `.env*` (PreToolUse) but an agent could still **read** real secrets — closing the gap matches the universal pattern used by the reference services. `.env.example`/`.env.default` remain readable. Lint (`check_scaffold_seeds_complete_harness`) now requires the deny block.
- **Scoped skills enforcement (least-agency / OWASP Agentic ASI02).** All seeded project skills (`api-verify`, `nest-verify`, `next-verify`, `vite-verify`, `next-migrate` in both scaffold and migrate) now declare a tightly-scoped `allowed-tools:` line (e.g. `Bash(pnpm *)`, `Bash(python *), Bash(ruff *)`). Previously they declared none and inherited unrestricted tool access — templateCentral preached scoping in its Skills Security section but did not model it in the skills it seeds.
- `scripts/lint-skills.sh`: `check_seeded_skills_scope_tools` — every seeded `*-verify`/`*-migrate` skill must declare a scoped `allowed-tools:`; and `check_no_unscoped_bash_grant` — no `allowed-tools:` may grant bare `Bash` (must be `Bash(...)`).
- `scripts/lint-skills.sh`: `check_scaffold_seeds_complete_harness` — every scaffold + migrate `settings.json` template must seed the complete enforcement hook set (PreToolUse secrets guard + `--no-verify` block, `UserPromptSubmit` injection firewall, `PostToolUse` typecheck, `Stop` test gate, `SessionStart` context recovery, `skillListingBudgetFraction`). Previously verified only by the audit's manual Step 3H checklist; now lint-enforced so an edit can't silently ship a harness with a hole.

### Fixed

- `skills/scaffold/fastapi/source-files.md`: removed duplicate `strict-transport-security` entry in `_SECURITY_HEADERS` — scaffolded FastAPI apps were emitting the HSTS header twice.
- `.claude/rules/nextjs.md`: pinned Next.js to `≥16.2.6` (16.2.5 is insecure for Turbopack deployments — App Router prefetch auth-bypass and WebSocket SSRF advisories).
- Version-marker drift: `templatecentral_version` was stale at `4.0.0` in all four scaffold templates, the migrate template, and the repo's own `.claude/harness.json`; README badge and `plugin.json` now aligned. All `templatecentral_version` fields and the README badge synced to `4.5.0`. The AGENTS.md `@4.0.0` schema-floor marker intentionally left pinned.

### Changed

- `skills/scaffold/{fastapi,nestjs,nextjs}/source-files.md`: documented `TRUST_PROXY` one-hop (ALB → App) vs two-hop (ALB → Traefik → App) topologies inline at each proxy-config site.
- `AGENTS.md` + `README.md`: surfaced harness **adoption/retrofit** as a discoverable intent routing to `templatecentral:migrate` — recovering the harness into a project built without templateCentral was already supported by `migrate` (Phases 1–5) but was not discoverable in the routing tables.
- Scaffold seam footers made timeless (`None activated.` instead of `None activated in v4.0.`) so generated projects don't ship version-stamped status text that drifts.

---

## [4.4.0] — 2026-06-04

### Security

- All 4 scaffold `settings.json` templates + `migrate/general`: added `PreToolUse` handler with `matcher: "Bash"` that blocks any bash command containing `--no-verify` (reads `tool_input.command` — not top-level `command`). Without this guard, agents could bypass Stop and all other hooks via `git commit --no-verify`.
- `skills/scaffold/fastapi/source-files.md`: added `strict-transport-security: max-age=31536000; includeSubDomains` to `SecurityHeadersMiddleware` — FastAPI scaffold was the only stack missing HSTS (NestJS/Next.js/Vite-React all had it).

### Fixed

- `.claude/rules/fastapi.md`: Starlette version updated from `1.0` to `≥1.1.0` — Starlette ≤1.0.0 is vulnerable to GHSA-86qp-5c8j-p5mr (malformed Host header auth-bypass; avoid `request.url.path` for auth-critical path matching, prefer `scope["path"]` or endpoint-level `Depends()`/`Security()`).
- `skills/migrate/general/implementation.md`: updated both TS and FastAPI `settings.json` templates to match scaffold — converted PreToolUse hooks from shell-string to args[] exec form, added block-`--no-verify` Bash guard, added `UserPromptSubmit` prompt-injection firewall, added `skillListingBudgetFraction: 0.02`.

### Added

- All 4 scaffold `settings.json` templates: added top-level `"skillListingBudgetFraction": 0.02` — caps skill-listing context overhead for projects that install multiple plugins.
- `scripts/lint-skills.sh`: new `check_no_toplevel_command_in_hooks` check (TIMELESS) — catches hook commands that read bash input from top-level `d.command` instead of `d.tool_input.command`, which silently returns empty string and defeats the hook.
- `skills/audit/implementation.md` (v2.4.0): added block-`--no-verify` harness check item to Step 3H; updated changelog.
- `skills/add/database/python/sqlalchemy-iam.md`: added "Sync vs async" rationale note near `list_users` and auth routes — the file is loaded independently so the reasoning was missing for IAM-auth projects.
- `skills/add/database/python/sqlalchemy.md`: added "Sync vs async" rationale note after auth routes block (`register`/`login`/`get_me`) — note previously only appeared near `list_users`, leaving the auth section without explanation.

### Changed (FastAPI async route handler consistency)

Route handlers that perform or will eventually perform I/O now use `async def` consistently — `def` is reserved for sync SQLAlchemy handlers (where FastAPI thread-pool semantics are the correct choice, and where an explanatory note is present). Affected files:

- `skills/add/endpoint/implementation.md`: `def my_endpoint` → `async def`
- `skills/add/auth/fastapi.md`: `def register`, `def login`, `def get_me` → `async def`; added `response_model=TokenResponse` to rate-limiter snippet
- `skills/add/logging/fastapi.md`: added `response_model` to `/login`, `/logout`, `/token/refresh` examples
- `skills/add/pagination/fastapi.md`: `def list_projects` → `async def`
- `skills/scaffold/fastapi/source-files.md`: `def example_endpoint` → `async def`
- `skills/migrate/nextjs-backend-extraction/fastapi.md`: added `response_model=` to all three user CRUD routes and the `/repos` integration route
- `skills/standards/validation-patterns/fastapi.md`: added `response_model=` to `/upload` and form-data `/login` examples
- `skills/scaffold/fastapi/source-files.md`: `def home`, `def health` → `async def` for consistency with `example_endpoint`

---

## [4.3.0] — 2026-06-04

### Added
- `skills/scaffold/nextjs/config-files.md`: `poweredByHeader: false` added to `next.config.ts` — removes the `X-Powered-By: Next.js` response header, eliminating a fingerprinting vector
- `skills/scaffold/nextjs/config-files.md`: commented `images.remotePatterns` placeholder added to `next.config.ts` — prevents surprise runtime errors for projects using `next/image` with external URLs
- `skills/scaffold/vite-react/config-files.md`: commented `server.proxy` skeleton added to `vite.config.ts` — standard starting point for proxying API calls to a backend (FastAPI/NestJS) during local dev
- `skills/scaffold/vite-react/config-files.md`: `preview: { port: 3000 }` added to `vite.config.ts` — aligns `vite preview` port with the dev server so production-build testing is consistent

### Changed
- `skills/scaffold/vite-react/config-files.md`: nginx image bumped from `nginx:1.28.3-alpine3.23` to `nginx:1.30.2-alpine3.23` — stable branch advanced two minor versions
- `skills/scaffold/fastapi/config-files.md`: Python image bumped from `python:3.13.3-slim` to `python:3.13.13-slim` — latest patch on the 3.13 LTS line

---

## [4.2.0] — 2026-05-30

### Added
- `scripts/pre-guard.sh` — centralised PreToolUse guard for templateCentral's own harness: blocks `.env*` (except `.env.example`), `.github/workflows/`, cert files (`.pem`/`.key`/`.p12`/`.pfx`/`.secret`), and credential files (`credentials.json`/`.netrc`/`.secrets`). All other paths — skills, specs, tests, app code — exit 0 immediately.
- `.claude/settings.json`: added **PreToolUse hook** wired to `scripts/pre-guard.sh` — templateCentral's own repo now enforces the same sensitive-path guard it seeds into scaffolded projects.
- All 4 scaffold stacks + migrate: **`.agents → .claude` symlink** created after harness bootstrap (`ln -s .claude .agents`) — makes `AGENTS.md`, `settings.json`, `rules/`, `skills/`, and `hooks/` discoverable by any agent framework that resolves from `.agents/`. One source of truth, zero duplication.
- All 4 scaffold stacks + migrate: **context load order note** appended to the `## AI Harness` block in the scaffolded `AGENTS.md` template — documents the full instruction chain (`managed policy → ~/.claude/CLAUDE.md → CLAUDE.md @AGENTS.md → AGENTS.md → .claude/rules/*.md`) and explicitly states that `CLAUDE.md` is optional and that hard enforcement lives in `settings.json` hooks only.

### Changed
- All 4 scaffold stacks + migrate: **PreToolUse guard expanded** — previously blocked `.env*` only; now also blocks `.github/workflows/`, cert files (`.pem`/`.key`/`.p12`/`.pfx`/`.secret`), and credential files (`credentials.json`/`.netrc`/`.secrets`). Skills, specs, tests, and all application code remain unrestricted (exit 0).
- All 4 scaffold stacks: **merge instruction corrected** — "merge the `PostToolUse` hook" → "merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, Stop, PostCompact)". Previously, running scaffold on a project with an existing `settings.json` silently skipped four of the five hooks.

### Fixed
- All description strings in scaffold and migrate referencing `PreToolUse` updated to accurately reflect expanded protection scope (was `.env*` only).

---

## [4.1.0] — 2026-05-28

### Security
- `skills/scaffold/*/source-files.md` (all 4 stacks): added **`UserPromptSubmit` hook** to scaffolded `.claude/settings.json` — pattern-checks incoming prompts for obvious injection phrases (`ignore previous instructions`, `you are now a`, etc.) and exits 2 to block. Uses args[] exec form (execve, no shell interpolation). Addresses OWASP LLM01 Prompt Injection at the harness entry point. TS stacks use `node -e`, FastAPI uses `python3 -c`.
- `skills/audit/implementation.md` Step 3H: added **UserPromptSubmit hook present** check — auditors now verify scaffolded harnesses include the LLM01 injection firewall
- `skills/add/ai-security/implementation.md`: added **LLM04 — Data and Model Poisoning** section — OWASP LLM Top 10 v2.0 coverage was incomplete (file jumped LLM03 → LLM05); LLM04 guidance covers: hash-verified RAG corpus ingestion, document sanitisation before embedding, output drift monitoring for production poisoning detection
- `skills/standards/code-standards/fastapi.md`: added **Starlette ≥1.1.0 required** rule — published advisory GHSA-86qp-5c8j-p5mr (2026-05-23) shows malformed `Host` headers in Starlette ≤1.0.0 cause `request.url.path` to return incorrect values, enabling middleware-based path auth bypass. Guidance added: prefer endpoint-level `Depends()`/`Security()` over middleware path-matching for auth-critical routes; `scope["path"]` is safe in middleware when path inspection is needed.

### Added
- `scripts/lint-skills.sh`: added **`check_no_tanstack_isInitialLoading`** check (ECOSYSTEM-ERA) — `isInitialLoading` was deprecated in TanStack Query v5 and removed in v6; skill files must use `isPending` instead. Now 22 lint checks total.
- `skills/audit/implementation.md` Step 3H: added **hook `"if"` field pre-filtering** check — auditors now verify that path-sensitive hooks (e.g. PreToolUse `.env` protection) document the `"if"` field option for reducing unnecessary process spawns and shrinking inline logic attack surface (ASI02 defence)
- `skills/review/review/implementation.md`: added **monorepo handling** to Stack Detection — if multiple stack markers are present (e.g. both `next.config.ts` and `vite.config.ts`), the review agent now asks the user which stack to review before proceeding (mirrors `templatecentral:migrate` behaviour)
- `scripts/validate-manifest.sh` — validates `.claude-plugin/plugin.json` and `marketplace.json` before publish: JSON syntax, required fields, semver format, skills directory existence, `plugins[]` entry completeness, name consistency across both files, and SKILL.md frontmatter correctness. Skips agent utilities (SKILL.md files without YAML frontmatter) as intentional unregistered internals.
- `skills/add/ai-security/implementation.md`: added `### LLM09 — Misinformation` section (hallucination mitigation: system prompt grounding, factual cross-referencing, human review gate for high-stakes domains) — previously the file covered LLM08 then jumped to LLM10, leaving a gap in OWASP LLM Top 10 v2.0 coverage
- `skills/review/review/implementation.md`: Layer 3 AI/LLM security checks — triggered when AI integrations are present: prompt injection (LLM01), excessive agency (LLM06), sensitive data leakage (LLM02), insecure output handling (LLM05)
- `skills/audit/implementation.md` v2.3.0: Step 6 now checks for `skillListingBudgetFraction` in `.claude/settings.json` (recommended for 10+ skill repos)

### Fixed
- `EXAMPLES.md`: replaced all ghost skill names (`templatecentral:nextjs-add-auth`, `templatecentral:shared-drift-check`, etc.) with current v4 names (`templatecentral:add`, `templatecentral:scaffold`, `templatecentral:standards`)
- `EXAMPLES.md`: FastAPI section version corrected from Python 3.12 to Python 3.13 (matches scaffold)
- `README.md`: FastAPI scaffold line corrected from `Ruff + Mypy` to `Ruff + Pyright` — scaffold generates pyright, not mypy
- `README.md`: "10 skills are registered automatically" → "all 10 skills are available automatically" — only 6 have frontmatter (registered); 4 are agent utilities
- `README.md`: `scripts/` directory added to Repository Structure tree with descriptions for both scripts
- `CONTRIBUTING.md`, `README.md`: contributor workflow updated to include `bash scripts/validate-manifest.sh` alongside `lint-skills.sh`
- `.github/workflows/validate-skills.yml`: frontmatter check now skips agent utilities (SKILL.md files without YAML `---` first line); added `validate-manifest` step calling `bash scripts/validate-manifest.sh`; path trigger widened from `plugin.json` to `.claude-plugin/**`
- `skills/scaffold/vite-react/config-files.md`: nginx image bumped from `1.28.2-alpine3.23` to `1.28.3-alpine3.23` (current on Docker Hub)
- `skills/write-skill/SKILL.md`: corrected OWASP Agentic ASI02 name from "Unconstrained Agent Actions" to "Tool Misuse & Exploitation" (official 2026 edition name); Least Agency rationale preserved
- `skills/standards/code-standards/fastapi.md`: explicit ban on deprecated `@app.on_event("startup/shutdown")` — removed in Starlette 1.0; must use `lifespan` context manager
- `scripts/lint-skills.sh`: Starlette startup-event check now excludes `standards/code-standards` documentation (same pattern as `audit/implementation` exclusion)
- `.claude/settings.json` (templateCentral repo): added `skillListingBudgetFraction: 0.02` — caps skill-listing context overhead for this 10-skill repo
- `skills/add/auth/nextjs.md`: added Next.js ≥16.2.6 security requirement note (high-severity advisory — RSC prefetch bypass on Turbopack); rate-limit IP extraction now reads `X-Forwarded-For` header with TRUST_PROXY guidance
- `skills/add/error-handling/fastapi.md`: removed standalone `app = FastAPI(...)` example block that caused agents to create a second app instance; replaced with explicit "integrate into existing `start_application()`" pattern; request schemas changed from `BaseModel` to `BaseRequestSchema`; `response_model` added to route decorators; `_sanitize_errors()` now joins the full loc path with `.` (e.g., `'user.email'` not just `'email'`), preserving nested schema context for Pydantic v2 errors; `http_exception_handler()` now passes `headers=dict(exc.headers) if exc.headers else None` to preserve `WWW-Authenticate` and other HTTP response headers on 401/403
- `skills/add/error-handling/nextjs.md`: added prominent dependency notice (`@testing-library/react`, `@testing-library/jest-dom`, `jsdom`) before ErrorBoundary tests; removed `as Record<string, string[]>` unsafe casts on `z.flattenError().fieldErrors`; updated `ErrorResponseBody` interface and `handleApiError` parameter to accept `Record<string, string[] | undefined>` (correct type from Zod)
- `skills/add/pagination/vite-react.md`: replaced `ENV.API_BASE_URL ?? ''` with `getApiBaseUrl()` — silent empty-string fallback hides misconfiguration at runtime; `(error as Error).message` unsafe cast replaced with `error instanceof Error` guard
- `skills/add/pagination/fastapi.md`: `page` field now has `le=10_000` upper bound — previously unbounded, allowing arbitrarily large page numbers
- `skills/add/pagination/nestjs.md`: exported `paginationSchema` from DTO; controller now uses `@Query(new ZodValidationPipe(paginationSchema))` — eliminates inline duplicate schema that omitted sort regex validation
- `skills/add/database/python/sqlalchemy-iam.md`: `_get_iam_token()` now wraps boto3 call in try/except, raising `RuntimeError` with clear message instead of crashing with an unhandled exception
- `skills/add/database/typescript/nextjs-drizzle.md`: added Drizzle v1.0.0-rc.1 pre-release notice and `drizzle-orm/zod` import path change
- `skills/add/database/typescript/nestjs-drizzle.md`: "pin to specific RC version" now includes concrete syntax example (`"drizzle-orm": "1.0.0-rc.1"`)
- `skills/add/api-route/implementation.md`: removed duplicate `## Validate` section at end of file (DRY violation — same content covered in `### 6. Validate`)
- `skills/add/logging/nestjs.md`: removed `(req as any)` cast; replaced with typed `FastifyRequest & { user?: { id: string } }` intersection type
- `skills/add/logging/fastapi.md`: added middleware ordering note — `@app.middleware("http")` is LIFO; must be placed before `add_middleware()` calls to wrap requests outermost
- `skills/add/integration/vite-react.md`: removed ghost skill name `full-stack-pairing` (no such skill exists); replaced with actionable guidance
- `skills/standards/validation-patterns/fastapi.md`: request body schemas changed from `BaseModel` to `BaseRequestSchema` (`CreateProjectRequest`, `LoginRequest`); `ProjectResponse` now documents when to use `BaseResponseSchema` vs `BaseModel` for response schemas (camelCase serialization needed for JS frontends)
- `skills/migrate/general/implementation.md`: Phase 4b now backs up `AGENTS.md` to `AGENTS.md.bak` before replacement (ASI08 rollback); removed vestigial `FUTURE.md` reference from Phase 0 v4.0 upgrade prompt
- `skills/migrate/nextjs-backend-extraction/nestjs.md` + `fastapi.md`: Phase 2 now creates a git backup branch before destructive migration (ASI08); git backup now saves `initial_branch=$(git rev-parse --abbrev-ref HEAD)` and restores with `git checkout "$initial_branch"` — eliminates `git checkout -` ambiguity when user had previously switched branches
- `skills/review/review/implementation.md`: corrected Layer 3 "insecure output handling" tag from `LLM02/LLM07` to `LLM05` (LLM07 is System Prompt Leakage in OWASP LLM Top 10 v2.0)
- `skills/cleanup/remove-example/implementation.md`: added "do not delete auth" note to Next.js section (was only in Vite section); `src/features/auth/` is intentional scaffold code in both stacks
- `skills/scaffold/nestjs/config-files.md`: `@typescript-eslint/no-explicit-any` changed from `'off'` to `'warn'`; `allowBuilds` comment now cross-references `templatecentral:add (auth)` for argon2 connection
- `skills/scaffold/{nestjs,nextjs,vite-react}/source-files.md` + `skills/scaffold/fastapi/source-files.md`: PreToolUse `.env` guard hook converted to `args[]` exec form (`["node","-e","..."]` / `["python3","-c","..."]`) — uses execve() instead of shell subprocess, eliminates shell injection risk (v2.1.139+, May 2026)
- `skills/scaffold/vite-react/source-files.md`: FetchClient URL construction now normalizes trailing/leading slashes — `baseUrl.replace(/\/$/, '')` + `path.replace(/^\//, '')` prevents double-slash URLs
- `skills/add/ai-security/implementation.md`: jurisdiction-specific comment on national-ID regex replaced with locale-neutral phrasing ("broad pattern — refine for your locale's format")

### Audit infrastructure
- `scripts/lint-skills.sh`: added `check_no_env_api_base_url_fallback` (ECOSYSTEM-ERA, check 17) — catches `ENV.API_BASE_URL ?? ''` anti-pattern in Vite skill files; added `check_owasp_llm_sections_complete` (TIMELESS, check 5) — verifies all LLM01–LLM10 sections present in `add/ai-security/implementation.md`
- `skills/audit/implementation.md`: added 3 new harness engineering checks (args[] exec form for PreToolUse hooks, SubagentStop wiring, skillListingMaxDescChars pairing); added Starlette ≥1.1.0 check to FastAPI-specific additional checks; updated ai-security cross-stack check to note LLM01–LLM10 lint enforcement
- `.claude/audit-ecosystem-research.md`: updated with May 2026 findings — args[] exec form (v2.1.139), SubagentStop/ConfigChange/WorktreeCreate/WorktreeRemove/MessageDisplay/Elicitation events, corrected hook event count (27+), AAIF 190+ orgs/60,000+ repos, Starlette advisory GHSA-86qp-5c8j-p5mr
- Confirmed via official Zod v4 docs: `z.iso.datetime()` and `z.email({ error: ... })` are correct v4 API — false-positive findings from agents with stale training data documented in research cache
- Confirmed via OWASP LLM Top 10 v2.0: LLM03 (Supply Chain) is a real category — `add/ai-security/implementation.md` was already correct

---

## [4.0.0] — 2026-05-26

### Harness Engineering

All 4 scaffold skills now emit a full harness layer into the scaffolded project.

**Compressed AGENTS.md** — replaced verbose 61-line template with a ~70-line indexed format: Commands section, two-table skill routing (project skills first, plugin skills second), file layout, rules, AI harness section. Subagent blind-spot note added (built-in subagents `/explore`/`/plan` have `omitClaudeMd: true` since v2.1.84 — all routing stays in AGENTS.md, not CLAUDE.md).

**CLAUDE.md = `@AGENTS.md`** — one line. Claude Code expands it fully at session start; `@`-import is officially documented. Verbose generated CLAUDE.md removed.

**Skill scoping model** — scaffolded AGENTS.md explicitly documents the priority chain:

| Level | Location | Invoked as |
|-------|----------|------------|
| Project | `.claude/skills/` | `/name` (overrides user) |
| User | `~/.claude/skills/` | `/name` |
| Plugin | `<plugin>/skills/` | `plugin:name` (namespaced, no conflict) |

Agents check `.claude/skills/` first for project-specific workflows, then use `templatecentral:*` for framework-level operations.

**Hook layer (PreToolUse → PostToolUse → Stop → PostCompact)** — all 4 stacks:
- PreToolUse: blocks edits to `.env*` files (exit 2); `.env.example` always allowed. Prevents AI from accidentally exposing secrets.
- PostToolUse: fast type feedback only. TS: `pnpm exec tsc --noEmit --incremental` (2–5s). FastAPI: `python -m pyright src/` (pyright is 2-5x faster than mypy).
- Stop hook: full test suite. Writes output to stderr, exits 2 when tests fail (forces Claude to fix), exits 0 on pass. Pattern: `OUTPUT=$(cmd 2>&1); EC=$?; echo "$OUTPUT" | tail -20 >&2; [ $EC -ne 0 ] && exit 2 || exit 0`.
- PostCompact: re-injects first 30 lines of AGENTS.md after context compaction so routing context survives summary. Note: PostCompact receives only metadata on stdin — `compacted_content` is not available (open GitHub issues #14258, #40492 request this).

**Seeded project skills** — All 4 scaffold skills seed a `*-verify` project skill at scaffold time (next-verify, nest-verify, api-verify, vite-verify). Next.js also seeds `next-migrate`. Each scaffold step prompts the user to create additional project skills for repeated workflows. `templatecentral:migrate` Phase 4 seeds the same skills when upgrading pre-4.0 projects.

**`harness.json`** — `.claude/harness.json` written at scaffold time with SHA-256 origin hashes of seeded files: AGENTS.md, CLAUDE.md, `.claude/settings.json`, and the stack's `*-verify.md` skill. `templatecentral:migrate` Phase 5 reads hashes to report UNCHANGED/MODIFIED/MISSING drift per file. FastAPI/NestJS/Vite-React were missing `settings.json` tracking; fixed.

**`templatecentral:migrate` Phase 4 expanded** — when upgrading pre-4.0 projects: seeds CLAUDE.md, project skills, harness.json alongside settings.json. Phase 5 (new): harness health check.

**`templatecentral:audit` Step 3H** — 12 harness engineering invariant checks (expanded from 10): adds Stop hook exit-2-on-failure pattern check (with correct stderr routing and exit code capture), PreToolUse `.env` protection check (correct `tool_input.file_path` field), PostCompact hook presence check, and harness.json `settings.json` tracking check. Step 6 (new): repo harness health check. Step 5 gains skill-gap suggestion.

**Skills Security guidance** — All 4 scaffold AGENTS.md templates now include a `## Skills Security` section (Snyk ToxicSkills 2026: 13.4% of published agent skills have critical vulnerabilities; 91% of malicious skills contain prompt injection). Guidance: review SKILL.md before installing, scope `allowed-tools:` tightly, avoid skills with unscoped network access.

### Marketplace Readiness

- README version badge updated to 4.0.0; CONTRIBUTING.md scaffold path corrected to `skills/scaffold/<stack>/`
- Added `LICENSE` (MIT), `SECURITY.md`, `CODE_OF_CONDUCT.md`, `EXAMPLES.md`
- `.github/workflows/ai-review.yml` — Claude AI PR review on every non-draft PR
- `plugin.json` — added `displayName`, `homepage`, `repository`, `license`, `$schema` fields
- `marketplace.json` — corrected skill count to "10 registered skills"

### Repository Dog-Fooding

- Repo AGENTS.md: compressed 229 → 65 lines with skill-scoping model, CLAUDE.md blind-spot note
- Repo `CLAUDE.md` = `@AGENTS.md`
- Repo `.claude/settings.json`: PostToolUse runs `lint-skills.sh` after every edit
- Repo `.claude/harness.json`: version manifest
- `.claude/rules/*.md` paths fixed (`skills/<stack>-*/**` → `skills/**`) — rules were never matching the actual skill directory structure; ghost skill names in rules files updated to current `templatecentral:*` names
- `docs/superpowers/` removed — stale planning artifacts from v3.1.0 development (feature already shipped)
- `CONVENTIONS.md` Section 3: documented new frontmatter fields (`when_to_use`, `paths`, `allowed-tools`, `argument-hint`) from Claude Code v2.1.84+
- `write-skill/SKILL.md`: added `when_to_use`, `disable-model-invocation`, `allowed-tools` guidance

### Security & Accuracy Fixes (audit passes, May 2026)

**HIGH — would break generated code**
- Ghost skill names (~80 files): all `shared-*-agent`, `templatecentral:shared-migrate`, `<stack>-scaffold`, `shared-add-*` forms replaced with correct v4 names
- NestJS Fastify filter: `extends BaseExceptionFilter + super.catch()` → `implements ExceptionFilter` (Fastify incompatible)
- Zod v4 form types: `z.infer` → `z.input` for React Hook Form schemas with `.default()` transforms
- `add/auth/nextjs.md`: `@better-auth/drizzle` (nonexistent) → `@better-auth/drizzle-adapter`

**Security**
- ErrorBoundary production leaks (vite-react, nestjs error-handling): `error.message` / component stack guarded with `DEV` checks
- OWASP LLM Top 10 v2.0 added to `add/ai-security`; LLM07 System Prompt Leakage added; Agentic Top 10 2026 entries added
- NIST SP 800-63B references replaced with "OWASP recommendation" across all auth skills (jurisdiction neutrality)

**Accuracy**
- FastAPI pagination: sync SQLAlchemy as primary path (async was the only runnable path shown but scaffold default is sync)
- NestJS `TRUST_PROXY`: numeric string → `parseInt()` guard for Fastify hop-count mode
- FastAPI `model_post_init(self, _)` → `model_post_init(self, __context: Any)` (correct Pydantic v2 signature)
- Various field path, import, and API name fixes across pagination, logging, error-handling skills

### Mutation Testing

New `templatecentral:add` capability: `mutation` — StrykerJS 7.x (TS stacks) and mutmut 3.5.0 (FastAPI). Report-only by default (`thresholds.break: null`); never blocks builds.

### Audit Pass — Round 6 — 2026-05-26

Fresh internet research pass (web scan of all frameworks, libraries, harness engineering, OWASP) + full semantic review across all 4 stacks. 17/17 lint checks clean.

**Harness engineering (skill scoping + new features)**
- **Skill scoping priority corrected**: Official order is `Managed > CLI > Project > User > Plugin`. Project skills (`.claude/skills/`) override user/personal skills (`~/.claude/skills/`) when names collide — previous documentation had this backwards ("Personal overrides project"). Updated `AGENTS.md` scoping table and `CHANGELOG`.
- Audit checklist Step 3H expanded: added skill scoping priority check, hook types check (5 total: command/http/mcp_tool/prompt/agent), Stop hook 8-block cap note (v2.1.143), PreCompact-can-block note, and omitClaudeMd scope clarification (only Explore+Plan skip CLAUDE.md).
- Ecosystem cache updated with complete harness findings: asyncRewake/async hook options, args:[] exec form, PreCompact blocking, Stop 8-block cap, skillListingBudgetFraction, parentSettingsBehavior, pnpm 11.0 breaking changes (Node.js ≥22 requirement, ESM-only, config split, new security defaults).

**Security — OWASP**
- `add/ai-security/implementation.md`: Expanded OWASP Agentic Top 10 2026 from prose description to full ASI01–ASI10 table with mitigation focus per entry. Updated Rules to reference "ASI01–ASI10 (Least-Agency principle)" explicitly.
- Audit checklist: confirmed OWASP Web 2025 (A03 renamed "Software Supply Chain Failures"; A10 new "Mishandling of Exceptional Conditions") and OWASP Agentic 2026 ASI prefix codes.

**Accuracy**
- `standards/drift-check/implementation.md`: `pip-audit -r` → `pip-audit --requirement` for consistency with `review/update/implementation.md`.

### Audit Pass — Round 7 — 2026-05-26

Full semantic review of all 50+ skill files against fresh research findings. 17/17 lint checks clean.

**Quality / parity**
- `scaffold/nestjs/config-files.md` pnpm-workspace.yaml: added `allowBuilds` comment section (parity with Next.js and Vite-React templates). NestJS auth uses `argon2` (native addon); users need the allowBuilds pattern to enable it.
- `migrate/general/implementation.md`: "conditional reinject" → "re-injects AGENTS.md after compaction" — stale wording from the abandoned stdin-aware PostCompact experiment.

**Confirmed CLEAN (fresh audit)**
- All 4 scaffold AGENTS.md templates correctly list project skills first, no old Personal/Project ordering
- All 3 API stacks (FastAPI, NestJS, Next.js): TRUST_PROXY documented for both one-hop and two-hop topologies
- All 4 scaffold AGENTS.md templates contain `## Skills Security` section
- Error boundary `error.message` guarded by `NODE_ENV === 'development'` / `import.meta.env.DEV` across all stacks
- Logging skills use only `user_id` (opaque identifier) — no email, password, token in log field examples
- Drizzle v1 casing API change documented in nestjs-drizzle.md; no deprecated `drizzle({ casing })` pattern
- better-auth `freshAge → createdAt` (v1.6.0) correctly documented in auth/nextjs.md
- No deprecated TanStack Query callbacks (onSuccess/onError on useQuery/useMutation) in any skill
- No Babel dependencies in Vite-React scaffold (correctly removed for plugin-react v6/Oxc)
- JWT algorithm whitelist present in FastAPI (algorithms=[ALGORITHM]) and NestJS (algorithms: ['HS256'])

### Audit Pass — Round 8 — 2026-05-26

DRY/YAGNI analysis, token-efficiency pass, new preventive lint rules. 19/19 lint checks clean.

**Lint (scripts/lint-skills.sh) — 19 checks (was 17)**
- `check_no_starlette_startup_events` — catches `@app.on_event`, `add_event_handler`, `on_startup=`, `on_shutdown=` (Starlette 1.0.0 removed these; use `lifespan=` exclusively). ECOSYSTEM-ERA.
- `check_no_fastapi_orjson_response` — catches `ORJSONResponse`/`UJSONResponse` (deprecated FastAPI 0.130+; native Pydantic Rust serializer replaces them). ECOSYSTEM-ERA.

**Quality**
- `scaffold/nestjs/config-files.md` pnpm-workspace.yaml: added `allowBuilds` example comment (parity with Next.js/Vite-React; NestJS auth uses `argon2` native addon).
- `migrate/general/implementation.md`: removed stale "conditional reinject" wording from PostCompact description.
- `add/ai-security/implementation.md` audit checklist updated: OWASP Agentic ASI01–ASI10 explicitly listed.

**Confirmed CLEAN — no action needed**
- No `ORJSONResponse`/`UJSONResponse` in any skills (preventive checks added)
- No Starlette deprecated startup event patterns in any skills
- No `npm_config_*` env vars in skills (pnpm 11 renamed to `pnpm_config_*`)
- `z.iso.datetime()` in validation-patterns/vite-react.md is CORRECT Zod v4 (audit agent false positive dismissed)
- NestJS `z.flattenError(zodError).fieldErrors` in error-handling/nestjs.md is CORRECT (audit agent false positive dismissed)
- No `isInitialLoading`, `cacheTime`, or `keepPreviousData` TanStack v4 APIs anywhere
- NestJS/Next.js/Vite-React `z.input` used correctly for form value types (not `z.infer`)

### Audit Pass — Round 10 — 2026-05-26 (final)

Final validation pass. 19/19 lint checks clean.

**Audit skill coverage gaps (MEDIUM)**
- `audit/implementation.md` Step 0b research checklist: added `TanStack Query` and `Vite + @vitejs/plugin-react` to the libraries scan list (both were in the ecosystem cache but not in the "what to research" prompt). Future fresh scans will now check for TanStack v6, Oxc/Rolldown bundler changes, and Babel-removal status.
- Step 0b: added `Claude Code harness engineering` as an explicit research category (hook events, hook types, new settings.json fields, skill scoping, Stop hook cap, AGENTS.md open standard status).
- Cache template (`0b` output format): added `### TanStack Query`, `### Vite + @vitejs/plugin-react`, and `## Claude Code Harness Engineering` sections so the generated cache file matches what is now researched.

**Confirmed CLEAN — final pass across all rounds 6–10 changes**
- AGENTS.md (repo): skill scoping priority correct (`Project > User`, not reversed)
- .claude/audit-ecosystem-research.md: ecosystem cache up to date for all researched categories including TanStack Query, Vite, and harness engineering
- add/ai-security: ASI01–ASI10 OWASP Agentic Top 10 table complete and accurate
- audit/implementation.md Step 3H: all 9 harness engineering invariant checks in place
- standards/drift-check: pip-audit flag consistent with review/update
- scaffold/nestjs/config-files.md: allowBuilds comment at parity with other stacks
- migrate/general/implementation.md: PostCompact wording accurate; all 5 sha256sum instances → shasum -a 256
- lint-skills.sh: 19 checks total (added Starlette startup events + ORJSONResponse in Round 8)
- All 5 scaffold sha256sum instances → shasum -a 256 (macOS portability)
- add/auth/vite-react.md: no duplicate Validate section

### Audit Pass — Round 9 — 2026-05-26

Cross-platform portability fix, DRY pass. 19/19 lint checks clean.

**Portability fix (HIGH)**
- `sha256sum` replaced with `shasum -a 256` across all 5 affected files: `migrate/general/implementation.md` (Phases 4f + 5b), `scaffold/fastapi/source-files.md`, `scaffold/nextjs/source-files.md`, `scaffold/vite-react/source-files.md`, `scaffold/nestjs/source-files.md`. `sha256sum` is not available on macOS by default; `shasum -a 256` works on both macOS and Linux and produces identical output format.

**DRY / YAGNI**
- `add/auth/vite-react.md`: removed duplicate `### Validate` section (6 lines). Step 7 already validates; "After Writing Code" dispatches `templatecentral:build`. No information lost.

**Confirmed CLEAN — no action needed**
- TanStack Query v5 compliance: all `useQuery` destructuring uses `isPending` (not deprecated `isLoading`); no deprecated `onSuccess`/`onError` on `useQuery` options
- Custom `isLoading` state in `AuthContext` (vite-react auth and scaffold) is a `useState` variable, not TanStack Query — no change needed
- `mutations.onError` in `QueryClient.defaultOptions` (error-handling/vite-react.md) is valid TanStack v5 API (not deprecated)
- No Zod v3 deprecated chained format methods (`z.string().email()`, `z.string().uuid()`, etc.) in any skill
- `api-route` correctly uses async `params: Promise<{ id: string }>` (Next.js 16)
- `add/form` correctly uses `z.input<typeof schema>` for React Hook Form value types
- Scaffold AGENTS.md templates correctly instruct agents to check `.claude/skills/` first, then `templatecentral:*` plugin skills
- `harness.json` SHA verification commands now confirmed `shasum -a 256` in all 5 files

### Audit Pass — Rounds 4–5 — 2026-05-26

Internet research pass + multi-round semantic review across all 4 stacks. All 16 lint checks clean.

**Hooks (all 4 stacks + migrate)**
- Stop hook was a no-op: result was piped through `tail` (always exits 0). Fixed: capture exit code → write stderr → `exit 2` on failure. Pattern: `OUTPUT=$(cmd 2>&1); EC=$?; echo "$OUTPUT" | tail -20 >&2; [ $EC -ne 0 ] && exit 2 || exit 0`.
- PreToolUse was reading wrong field: top-level `file_path` → `tool_input.file_path` from stdin JSON.
- `stop_hook_active` removed from Stop hook commands: not needed when hook exits 0 on test pass (no infinite-loop risk). Claude Code has 29 named hook events total.
- `MultiEdit` removed from matcher: not a real tool. `Edit|Write|MultiEdit` → `Edit|Write`.
- PostCompact hook added to all 4 scaffold + migrate: re-injects first 30 lines of AGENTS.md after compaction. (Note: PostCompact stdin has only metadata, not compacted_content — unconditional re-inject is correct.)
- Migrate Phase 4 brought to full hook parity with scaffold (PreToolUse + PostToolUse + Stop + PostCompact).
- PreToolUse `.env` protection added (was missing in all 4 scaffold + migrate templates).

**Security headers**
- Next.js `next.config.ts`: added `X-XSS-Protection: 0` (parity gap vs FastAPI/NestJS/Vite-React).
- Vite-React nginx: `X-Frame-Options: SAMEORIGIN` → `DENY`; added `Content-Security-Policy: frame-ancestors 'none'; base-uri 'self'; object-src 'none'`.

**Harness**
- `harness.json`: FastAPI/NestJS/Vite-React now track `.claude/settings.json` hash. Migrate Phase 4 `harness.json` now includes `*-verify.md` skill hash (was computed but omitted from output template).

**Accuracy**
- NestJS logging bootstrap: replaced full `bootstrap()` excerpt (had simplified TRUST_PROXY missing numeric string → `parseInt()` guard) with logger-wiring-only snippet. Prevents users from overwriting scaffold's correct proxy logic.
- `add/test/nextjs.md`, `add/test/vite-react.md`: `pnpm test` → `pnpm test --run` in verification steps (without `--run`, Vitest starts watch mode in a TTY).
- `test/implementation.md` (test agent): `pnpm test` → `pnpm test --run` in run step — same watch-mode issue; test agent was dispatching a blocking command.
- TanStack Query v5: `isLoading` → `isPending` in 3 files (`scaffold/nextjs/source-files.md` example component, `add/pagination/nextjs.md`, `add/pagination/vite-react.md`). `isLoading` was removed in TQ v5; `isPending` is the correct "initial load, no data yet" state.
- Audit checklist: 12 invariants — PostCompact check updated to verify stdin-aware pattern; removed `stop_hook_active` guard check; added PreToolUse `tool_input.file_path` field check.

### Lint (scripts/lint-skills.sh)

17 checks total (was 10 in v3). New checks added in v4:
- `check_no_ghost_agent_names` — extended to catch `*-code-standards`, `nextjs-add-auth` old names (TIMELESS)
- `check_no_zod_deprecated_message_key` (ECOSYSTEM-ERA)
- `check_no_middleware_ts` with exclusions for meta-documents
- `check_no_mypy_in_postToolUse` — enforces pyright over mypy (ECOSYSTEM-ERA)
- `check_no_postToolUse_full_test_suite` — test suites belong in Stop hooks (TIMELESS)
- `check_no_tanstack_isLoading` — catches TQ v5 `isLoading` from `useQuery`/`useMutation` destructuring (ECOSYSTEM-ERA)

---

## [3.2.0] — 2026-05-25

### Fixed — Ecosystem accuracy and correctness audit (3-iteration pass)

Full audit of all 50 skill files against the 2026-05-08 ecosystem research cache. 19 HIGH findings fixed in round 1, 8 new HIGHs surfaced and fixed in round 2, 1 residual HIGH fixed in round 3. Lint passes clean throughout.

**FastAPI**
- `add/database/python/beanie.md` — Replaced non-existent `AsyncMongoClient` (was `from pymongo import AsyncMongoClient`) with `AsyncMotorClient` from `motor.motor_asyncio`; added `motor` to requirements; fixed incorrect "Motor is no longer required" note; replaced Beanie 1.x `indexes = ["email"]` string syntax with correct `Annotated[EmailStr, Indexed(unique=True)]` field annotation; fixed `User.find_all()` (doesn't exist) → `User.find().to_list()`; narrowed bare `except Exception` to `except (ValueError, TypeError)` on ObjectId conversion
- `add/auth/fastapi.md` — Added `TRUST_PROXY: int` to `APISettings` and `.env` template; added concrete `.env` example next to rate-limit TRUST_PROXY warning so the fix is actionable
- `add/database/python/sqlalchemy-iam.md` — Fixed broken step numbering (A2 → A5 gap); now uses a consistent A1–A10 sequence
- `add/error-handling/fastapi.md` — Added prominent migration note explaining the response envelope change (default FastAPI `detail` format vs. custom `fieldErrors` envelope) so existing tests aren't silently broken; added note that the standalone `app = FastAPI(...)` example is a reference, not a file replacement
- `add/pagination/fastapi.md` — Corrected all file paths from non-existent `src/lib/` to correct `src/core/`; fixed `from core.database import get_session` → `from database.session import get_db`; added sync/async clarification notes; replaced `from core.exceptions import InvalidInputError` (undefined) with `HTTPException`; fixed `hasMore` → `has_more` with `serialization_alias='hasMore'`; removed conflicting flat `Query()` params — route now uses `Depends(PaginationParams)` consistently; fixed `scalar()` nullable → `scalar() or 0`

**NestJS**
- `add/module/implementation.md` — Added explicit `import { beforeEach, describe, expect, it } from 'vitest'` to Step 9 test template (was missing all vitest globals with `globals: false`)
- `add/test/nestjs.md` — Added vitest imports to all three test templates (Controller, Service, E2E); Service template had `vi` but was missing `describe`/`it`/`expect`/`beforeEach`
- `scaffold/nestjs/source-files.md` — Added `expect` to vitest import in `test/app.e2e-spec.ts` template
- `add/logging/nestjs.md` — Fixed Tier 1 `main.ts` snippet that dropped `FastifyAdapter` entirely (would silently switch app from Fastify to Express); fixed broken `trustProxy: !!process.env.TRUST_PROXY` coercion (now uses canonical two-line pattern that correctly handles `"false"`, `"0"`, and `"*"` values); added `BaseExceptionFilter` import to `HttpExceptionFilter`; fixed stale `See Also` skill aliases

**Next.js**
- `add/error-handling/nextjs.md` — Fixed `await auth()` with no arguments (TypeError) → `await auth.api.getSession({ headers: _request.headers })`
- `add/logging/nextjs.md` — Fixed invalid export syntax `export { GET: _GET as GET }` → `export { _GET as GET }`; fixed verification comment field name mismatch (`query_name` → `name`)
- `add/database/typescript/nextjs-kysely.md` — Added Zod `safeParse` + structured 400 response on POST (was using throwing `.parse()` with no try/catch); changed `selectAll()` → `.select(['id', 'email', 'name'])` in both API route and Server Component examples; changed `.returningAll()` → `.returning(['id', 'email', 'name'])`
- `add/database/typescript/nextjs-mongoose.md` — Added `.select('name email -_id')` to `User.find()` calls in both API route and Server Component examples

**Vite + React / Cross-stack**
- `standards/validation-patterns/patterns.md` — Fixed `z.email().toLowerCase()` crash (`.toLowerCase()` does not exist on `ZodEmail`) → `.transform(v => v.toLowerCase())`; fixed `z.uuid('...')` and `z.url('...')` invalid message-arg form for Zod v4
- `standards/validation-patterns/vite-react.md` — Fixed `z.infer` → `z.input` for form value types (avoids type errors when transforms are present); replaced raw `{...register(...)}` on `<input>` elements with `Form` + `FormField` + `CustomFormField` widget pattern
- `add/pagination/vite-react.md` — Made `usePagination` hook generic over `T` (was typed as `any`); updated `fetchFn` generic to include full `pagination` shape so `nextPage` and `hasMore` work correctly at runtime; added `z.flattenError` on `safeParse` failure

**Repository**
- `AGENTS.md` — Removed `thedotmack/claude-mem` recommendation (its UserPromptSubmit hook blocks user input); updated pnpm minimum from `≥10.33.2` to `≥11` (required for `allowBuilds` object form in `pnpm-workspace.yaml`)
- `.gitignore` — Added `.claude/settings.local.json` (machine-specific, not project config)

---

## [3.1.0] — 2026-05-13

### Added — Next.js Backend Extraction Migration

New skill path under `templatecentral:migrate` for extracting a Next.js BFF into a standalone backend service.

**New files:**
- `skills/migrate/nextjs-backend-extraction.md` — stack router: detects target backend (NestJS / FastAPI) from user intent and cats the appropriate leaf
- `skills/migrate/nextjs-backend-extraction/nestjs.md` — fully self-contained 10-phase NestJS migration guide
- `skills/migrate/nextjs-backend-extraction/fastapi.md` — fully self-contained 10-phase FastAPI migration guide

**What it does (10 phases):**
1. Assessment — scans `src/app/api/` routes and `src/integrations/` import graph; prints a structured report
2. Scope confirmation gate — user confirms before any files change
3. Scaffold sibling backend at `../[project-name]-api`
4. Migrate API routes → NestJS controllers/services/modules or FastAPI routers/services/schemas
5. Migrate integrations (API-route-imported only; frontend-only entries stay in Next.js)
6. Migrate database (NestJS: Drizzle or Mongoose; FastAPI: gated ORM choice — SQLAlchemy or Beanie)
7. Migrate auth (`proxy.ts` stays in Next.js; new backend auth module added)
8. Rewire Next.js as pure frontend (`NEXT_PUBLIC_API_URL`, delete `src/app/api/`)
9. Update CORS config and both `AGENTS.md` files
10. Verify: `pnpm build && pnpm test` both projects (FastAPI: `pytest`)

**Updated:**
- `skills/migrate/SKILL.md` — added backend-extraction routing case; updated description
- `skills/audit/implementation.md` — added 3 new reference files to the audit checklist

---

## [3.0.0] — 2026-05-09

### Breaking — Skill Registry Overhaul (57 → 6 registered skills)

All registered skill names have changed. Any saved invocations using the old names (`templatecentral:fastapi-add-auth`, `templatecentral:nestjs-add-test`, etc.) must be updated to use the new consolidated entry points below.

**New registered skills (6 total):**
| Skill | Replaces |
|---|---|
| `templatecentral:add` | `fastapi-add-auth/database/test/integration`, `nestjs-add-auth/database/module/test/integration`, `nextjs-add-auth/database/api-route/component/page/feature/form/test/integration`, `vite-react-add-auth/component/page/feature/form/test/integration`, `shared-add-auth/database/test/integration/logging/error-handling/pagination/ai-security`, `shared-add-database-python`, `shared-add-database-typescript` |
| `templatecentral:scaffold` | `fastapi-scaffold`, `nestjs-scaffold`, `nextjs-scaffold`, `vite-react-scaffold` |
| `templatecentral:standards` | `fastapi-code-standards`, `nestjs-code-standards`, `nextjs-code-standards`, `vite-react-code-standards`, `shared-code-standards`, `shared-validation-patterns`, `shared-drift-check`, `shared-full-stack-pairing` |
| `templatecentral:migrate` | `shared-migrate`, `shared-migrate-database` |
| `templatecentral:audit` | `shared-audit` |
| `templatecentral:write-skill` | (new) |

**De-registered as agent utilities (not user-invocable):** `build`, `test`, `review`, `cleanup` — agents cat these directly; they no longer appear in the skill listing.

### Changed — Architecture

- **Nested reference file architecture**: All implementation content moved out of registered SKILL.md routers into reference files under `skills/add/<capability>/<stack>.md` and `skills/add/<capability>/<stack>/<variant>.md`. Registered skills detect context and `cat` the right file; they contain no implementation prose.
- **3-level chain** for database (SKILL.md → stack router → ORM variant); **2-level chain** for all other capabilities (SKILL.md → stack file).
- **Progressive context loading**: Only ~6 skill descriptions load at session start (~300 tokens). Full implementation loads only when a skill is invoked.
- **CONVENTIONS.md** added at `skills/CONVENTIONS.md` — single source of truth for all skill authoring rules, nesting depth, description limits, and ref header format.
- **`skills/write-skill/SKILL.md`** added — authoring checklist enforcing conventions at creation time.
- **C1–C6 conventions checks** added to `shared-audit` → `templatecentral:audit`: description ≤150 chars, ref headers, SKILL.md body ≤30 lines, nesting depth ≤3, no duplicate content, jurisdiction neutrality (C6).

### Changed — Audit (`audit/implementation.md` v2.1.0)

- **Universal standards mandate**: All skills must be jurisdiction-neutral, industry-neutral, and free of region/country/ethnicity/gender/race-specific content. Security guidance follows OWASP (Top 10 web, LLM Top 10, Agentic Top 10) as the universal standard. Government-grade rigour (least privilege, defence-in-depth, audit logging, strong authentication) applied generically without naming any specific regulation.
- **Training cutoff**: Step 0 now states "August 2025" explicitly; all ecosystem state treated as potentially stale until confirmed by web search.
- **C6 — Jurisdiction neutrality check**: grep pattern added to catch known jurisdiction-specific framework names in skill files.
- **Step 4b**: minor fixes (single file, ≤10 lines) → fix directly, no plan required; large-scope → confirm first.
- **Step 4f**: changelog gate — verify `git status` is clean before writing the CHANGELOG entry.
- **Token efficiency**: expanded from one checkbox to five concrete sub-checks (line count, redundant comments, over-scaffolded examples, duplicate instructions, redundant prose).

### Fixed

- `add/database/python.md`, `add/database/typescript.md`: removed jurisdiction-specific compliance framework names (HIPAA, PCI) from database detection signal examples; replaced with generic high-security signal language (`regulated`, `iam`, `no-password`, `audit-logging`).
- `scripts/lint-skills.sh`: updated all `shared-audit` exclusion patterns to `audit/implementation` following path rename; added `audit/implementation.md` exclusion to jurisdiction check.

### Removed

- 31 retired skill directories (all replaced by reference files under the new nested structure).
- All completed planning and spec documents under `docs/superpowers/plans/` and `docs/superpowers/specs/` — superseded by current architecture.

---

## [2.13.1] — 2026-05-08

### Security
- `nestjs-add-auth`: `JwtStrategy` constructor now includes `algorithms: ['HS256']` — prevents algorithm confusion attacks where `passport-jwt` could accept unexpected signing algorithms
- `nextjs-add-auth`: `request.ip` in Upstash rate-limiting example now has a `TRUST_PROXY` note — without it, all clients share the reverse-proxy IP as the rate-limit key, making per-client limiting ineffective; one-hop (`TRUST_PROXY=true`) and two-hop (`TRUST_PROXY=2`) topologies documented

### Fixed
- **NestJS stack — Vitest migration (completing 2.2.0)**: `.claude/rules/nestjs.md`, `nestjs-add-module`, `nestjs-code-standards` updated "Jest" → "Vitest"; `nestjs-add-test` migrated `jest.fn()` → `vi.fn()`, `jest.spyOn()` → `vi.spyOn()` with `import { vi } from 'vitest'`; `jest-e2e.json` reference replaced with `vitest.config.e2e.ts`
- `nestjs-add-auth`: `ttl: 900_000` → `ttl: minutes(15)` using `@nestjs/throttler` `minutes()` helper — semantically equivalent, more readable
- `nestjs-scaffold`: `...globals.jest` removed from ESLint config template — project uses Vitest with `globals: false`; the Jest spread was unused and misleading; `@nestjs/platform-fastify` floor note moved to `.claude/rules/nestjs.md` per SSOT policy
- `vite-react-scaffold`: `Strict-Transport-Security` header added to nginx.conf — security header parity with NestJS and Next.js scaffolds
- `nestjs-add-database`, `nextjs-add-database`: Drizzle v1 "release-candidate" caveat removed — v1.0 is stable (released mid-2025)
- `shared-add-ai-security`: OWASP Top 10 for Agentic Applications (2026) reference added for Capability C systems; `z.array(z.string().url())` → `z.array(z.url())` (Zod v4 top-level form)
- `shared-add-error-handling`, `shared-add-logging`, `shared-validation-patterns`: `error.flatten()` → `z.flattenError(error)` throughout; `z.string().datetime()` → `z.iso.datetime()`; `import { z }` added where missing; password min-length updated to 12 in `shared-validation-patterns`

### Added
- `scripts/lint-skills.sh`: new mechanical lint script — 10 checks (timeless: CVE identifiers, jurisdiction-specific content, hardcoded secrets; ecosystem-era: version pins, bcrypt references, deprecated Zod `.flatten()`, `middleware.ts`, HTTP/1.0 cache headers, Jest APIs in Vitest projects, `globals.jest` in ESLint templates, timing-unsafe stored-secret comparisons, deprecated Zod v4 string-format methods)
- `skills/shared-audit/SKILL.md`: new structured audit skill — 5-step workflow (ecosystem research cache → mechanical lint → per-file semantic review → fix loop → infrastructure update); covers all 49 skills across 5 stacks
- `.github/workflows/validate-skills.yml`: `lint-patterns` job calling `bash scripts/lint-skills.sh skills/`; `scripts/**` added to path triggers
- `.claude/audit-ecosystem-research.md`: ecosystem research cache file (30-day TTL) — prevents redundant web scans on consecutive audit runs

---

## [2.13.0] — 2026-05-07

### Fixed
- `nestjs-scaffold`: added `Referrer-Policy: strict-origin-when-cross-origin` to Helmet config — `@fastify/helmet` does not set this header by default
- `nestjs-scaffold`: added `Permissions-Policy: camera=(), microphone=(), geolocation=()` to `onSend` hook — was missing while Next.js scaffold had it
- `nestjs-scaffold`: removed legacy `Pragma: no-cache` and `Expires: 0` from `onSend` hook — both deprecated in HTTP/1.1+; `Cache-Control` is sufficient
- `fastapi-scaffold`: added `Permissions-Policy` to `_SECURITY_HEADERS` — brings FastAPI in line with Next.js and NestJS scaffolds
- `nestjs-scaffold`, `nextjs-scaffold`, `vite-react-scaffold`: moved `blockExoticSubdeps` from `.npmrc` to `pnpm-workspace.yaml` — in pnpm 11, `.npmrc` is auth/registry-only; supply-chain protection was silently ignored
- `nestjs-scaffold`, `nextjs-scaffold`, `vite-react-scaffold`: added `pnpm-workspace.yaml*` to Dockerfile `COPY` line and `.dockerignore` exception list — pnpm config absent during Docker `pnpm install` was losing security settings
- `nestjs-add-auth`: updated `allowBuilds` guidance to use `pnpm-workspace.yaml` — `package.json#pnpm` field is no longer read by pnpm 11
- All three Node rules files (`.claude/rules/nestjs.md`, `nextjs.md`, `vite-react.md`): updated `allowBuilds` location reference to `pnpm-workspace.yaml`
- `fastapi-add-auth`: noted that `TRUST_PROXY` must be set for per-client rate limiting with `slowapi` when behind a reverse proxy
- `nestjs-add-auth`: noted same TRUST_PROXY dependency for `ThrottlerGuard` / Fastify `trustProxy` interaction
- `shared-drift-check`, `shared-update-agent`: replaced "CVE" identifiers with "security advisory" — prevents identifier drift in skills

### Changed
- `nestjs-scaffold`: removed `@nestjs/common` and `@nestjs/core` version pins from install command; removed `@fastify/helmet` version pin — version floors belong in rules, not skills
- `vite-react-scaffold`: removed `react-router`, `@hookform/resolvers`, `@vitejs/plugin-react` version pins from install command — arbitrary preferences, not functional constraints
- `nextjs-add-auth`: removed `better-auth@^1.6.9` pin — install unpinned; version belongs in rules if a floor is needed

---

## [2.12.0] — 2026-05-07

### Added
- `fastapi-scaffold`: `SecurityHeadersMiddleware` — zero-dependency ASGI middleware setting HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, and X-XSS-Protection on every HTTP response; wired via `configure_security_headers()` called before CORS in `start_application()`

### Fixed
- `nextjs-add-auth`: pinned `better-auth@^1.6.9` (was `@latest`) — removes non-deterministic installs; resolves to current stable
- All scaffolds: migrated pnpm native-addon config from `"onlyBuiltDependencies": [...]` array syntax (pnpm 10) to `"allowBuilds": { "<pkg>": true }` object syntax (pnpm 11)

---

## [2.11.0] — 2026-05-07

### Added
- `nextjs-scaffold`: new `src/lib/utils/request-origin.ts` — `getAppOrigin()` utility reads `X-Forwarded-Proto`/`X-Forwarded-Host` when `TRUST_PROXY` is set, falls back to direct connection values otherwise
- `nestjs-scaffold`: `TRUST_PROXY` env var wired into `FastifyAdapter({ trustProxy })` at bootstrap — no-op when unset; `*` correctly converts to boolean `true` for Fastify
- `fastapi-scaffold`: `ForwardedHostMiddleware` (fixes `X-Forwarded-Host` gap in uvicorn's `ProxyHeadersMiddleware`) and `configure_proxy_headers()` — both conditional on `TRUST_PROXY`; `TRUST_PROXY` field added to `APISettings`
- All three scaffolds: `TRUST_PROXY=` added to `.env.example` with explanation comment

---

## [2.10.0] — 2026-05-07

### Fixed
- `nestjs-add-database`: migrated all three AuthService replacement blocks (Drizzle, Kysely, Mongoose) from bcrypt to argon2id — resolves functional contradiction with nestjs-add-auth argon2 migration
- `fastapi-add-database`: replaced bcrypt placeholder comment with a reference to `hash_password()` from `core/security.py` — removes algorithm coupling from example code
- `nextjs-add-auth`: removed bcrypt hedge from password hashing rule — argon2id is the clear recommendation
- `shared-add-logging`: updated illustrative auth example from bcrypt.compare to argon2.verify
- `fastapi-code-standards`: removed FastAPI version number from Content-Type note — now version-agnostic

### Changed
- `fastapi-scaffold`, `shared-add-logging`: removed python-json-logger version floor from skills — version now in fastapi rules
- `fastapi-add-database`: removed pymongo version floor from skill — version now in fastapi rules
- `.claude/rules/fastapi.md`: added python-json-logger ≥4.0 and pymongo ≥4.0 to stack definition

---

## [2.9.0] — 2026-05-07

### Fixed
- `nextjs-add-database`, `nestjs-add-database`: restored Drizzle ORM v1 release-candidate warning — v1.0.0-rc.2 (May 2026); stable not yet shipped
- `fastapi-code-standards`: removed hardcoded Python 3.12 target from Ruff note — target version is project-configurable in ruff.toml
- `fastapi-add-auth`: removed PyJWT version pin from dependencies list — version belongs in rules, not skills

### Changed
- `fastapi-add-auth`: migrated password hashing from bcrypt to argon2id (`argon2-cffi`) — removes bcrypt 72-byte limit constraint; OWASP/NIST SP 800-63B recommended algorithm
- `nestjs-add-auth`: migrated password hashing from bcrypt to argon2id (`argon2` npm) — updated `onlyBuiltDependencies` from `bcrypt` to `argon2`; removed `@types/bcrypt`
- `fastapi-code-standards`: updated password hashing standard from bcrypt to argon2id

---

## [2.8.0] — 2026-05-07

### Fixed
- `fastapi-scaffold`, `nextjs-scaffold`, `nestjs-scaffold`, `vite-react-scaffold`: removed hardcoded `Asia/Singapore` timezone from Dockerfiles — containers now default to UTC; operators can override via `TZ` env var at deploy time
- `shared-add-ai-security`: replaced hardcoded `gpt-4o-2024-11-20` model snapshot in LLM03 and LLM10 examples with a placeholder annotation — the teaching point (pin a dated snapshot) is preserved without encoding a specific version
- `nextjs-add-auth`: removed `better-auth ≥1.6` and `better-auth 1.6` version markers from `freshAge` and OIDC provider notes — behavioral facts retained, drifting version pins removed
- `fastapi-scaffold`, `shared-add-logging`: updated `python-json-logger` floor from `>=3.3.0,<4.0` to `>=4.0` — v4.1.0 is current stable (March 2026)

---

## [2.7.0] — 2026-05-07

### Fixed
- `nextjs-add-database`, `nestjs-add-database`: retired Drizzle ORM v1 RC warning — v1.0 is now stable; retained casing API guidance and migration guide link
- `nestjs-add-auth`, `fastapi-add-auth`: added argon2id guidance note to Rules — argon2id is the current OWASP/NIST recommendation for new projects; bcrypt remains acceptable
- `shared-add-ai-security`: replaced Singapore-specific NRIC regex and phone country code with generic jurisdiction-neutral PII patterns
- `nextjs-add-auth`: removed hardcoded `v1.5` version pin from better-auth Drizzle adapter note

---

## [2.6.0] — 2026-05-07

### Fixed
- `shared-validation-patterns`: password `min_length` corrected from 8 to 12 to match all auth skill policies
- `fastapi-add-auth`: added algorithm whitelist comment to `jwt.decode()` — explains why `algorithms=` must never be omitted or broadened
- `nextjs-add-auth`: noted `@better-auth/drizzle` ships as a separate package since better-auth v1.5
- `nextjs-add-database`, `nestjs-add-database`: extended Drizzle v1 RC callout with rc.1 casing API breaking change and migration guide link
- `nestjs-add-auth`: added `pnpm.onlyBuiltDependencies` step for bcrypt — pnpm 10 blocks native builds by default
- `vite-react-scaffold`: added explicit `"types": []` to tsconfig — TypeScript 6 changed default from all visible `@types` to empty array

---

## [2.5.0] — 2026-05-07

### Fixed
- **rules/nextjs.md**: Updated `Node.js ≥20.9.0` → `Node.js ≥24` — Node 24 is Active LTS
- **rules/{nestjs,vite-react}.md**: Added `Node.js ≥24` to Stack lines — was missing entirely
- **{nextjs,nestjs,vite-react}-scaffold**: `engines.node` updated to `>=24`; Dockerfile ARG changed from patch-pinned `node:24.14-alpine3.23` to `node:24-alpine` — patch pins belong in CI/CD, not skill templates
- **{nestjs,vite-react}-scaffold**: Dockerfile `NODE` comment corrected — floating major tag, pin to digest in CI for reproducibility

### Added
- **nextjs-code-standards**: Async-only rule for Next.js 16 Request APIs (`cookies()`, `headers()`, `params`, `searchParams`) — sync access is a TypeScript error and runtime failure
- **nextjs-add-auth**: `@better-auth/oauth-provider` replaces the removed `oidc-provider` plugin (better-auth 1.6); added docs link
- **fastapi-code-standards**: `json=data` test client guidance — FastAPI 0.132+ enforces `Content-Type: application/json` by default (`strict_content_type=True`)
- **{nextjs,nestjs}-add-database**: Drizzle ORM v1 RC status callout — not yet final stable release
- **vite-react-scaffold**: Oxc note for `@vitejs/plugin-react` v6 — no Babel config or `@babel/core` required

---

## [2.4.0] — 2026-05-07

### Fixed
- **AGENTS.md**: Removed drifting patch-level Next.js version pin (`16.2.4+` / `15.5.9+`) — major version pins belong in `.claude/rules/*.md` only
- **rules/fastapi.md**: Tightened `Pydantic v2` to `Pydantic ≥2.9.0`; added `Starlette 1.0` to Stack line
- **rules/nextjs.md**: Added `Node.js ≥20.9.0` to Stack line — Next.js 16 dropped Node 18 support
- **fastapi-add-auth**: Removed `slowapi>=0.1.9` patch-level version pin (CVE policy violation)

### Added
- **AGENTS.md**: OWASP A03:2025 Supply Chain framing in supply chain section — supply chain attacks rose to #3 in 2025 ranking
- **shared-add-error-handling**: OWASP A10:2025 Mishandling Exceptional Conditions merged into Security Checklist (unified with existing unhandled-exceptions item)
- **nextjs-add-auth**: better-auth ≥1.6 `freshAge` behavioral note — `freshAge` now measures from `createdAt` not last activity
- **shared-add-ai-security**: AWS Responsible AI Lens section (re:Invent 2025) with all 10 dimensions — complements OWASP LLM Top 10

---

## [2.3.0] — 2026-05-06

### Fixed
- **All auth skills**: Removed hardcoded CVE notes for `drizzle-orm` and `better-auth` — CVE tracking belongs in `shared-drift-check` Step 6 (dynamic `pnpm audit` / `pip-audit`), not baked into skill files
- **All skills**: Stripped IM8 policy codes (AS-4, AS-5, AS-6, AS-8, AS-10, AS-11, AS-12, LM-1) from skill files — templateCentral is general-purpose; the security guidance is retained, the Singapore government attribution is removed
- **Four scaffold skills**: Vault note in generated AGENTS.md templates is now vendor-neutral ("use a secrets manager appropriate to your cloud platform") — no prescriptive AWS/Azure/GCP lock-in
- **shared-add-logging**: Log isolation section de-IM8'd; guidance preserved
- **AGENTS.md**: File upload malware scanning note de-IM8'd; guidance preserved

---

## [2.2.0] — 2026-05-06

### Security
- **Next.js scaffold**: Added HTTP security headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, HSTS, CSP baseline) via `next.config.ts` `headers()` — IM8 AS-10
- **NestJS scaffold**: Swagger `/docs` endpoint now disabled in `NODE_ENV=production`; expanded CSP directives (`default-src`, `script-src`, `object-src`, `img-src`)
- **Next.js scaffold**: `https-agent.ts` TLS now defaults to verified in all environments; opt-out via `NODE_TLS_REJECT_UNAUTHORIZED=0` only
- **CI**: `actions/checkout` pinned to SHA (supply chain: OWASP A03:2025); added hardcoded-secret scan job

### Added
- **Next.js scaffold**: `pino` structured logging baked in — `src/lib/logger.ts`, `src/lib/utils/with-logging.ts` (aligns with `shared-add-logging` skill requirements)
- **NestJS scaffold**: Pino `genReqId` for per-request correlation IDs (IM8 audit trail)
- **shared-add-ai-security**: New skill — OWASP LLM Top 10 v2.0 controls (prompt injection, PII redaction, output validation, tool allowlists, token budgets) for A/B/C capability tiers
- **shared-drift-check**: Step 6 — interactive security audit (`pnpm audit` / `pip-audit`) with OSV/NVD vulnerability check
- **AGENTS.md**: SBOM generation guidance (EU CRA / CSA AD-2026-003) and vulnerability scanning commands
- **IM8 AS-6**: Argon2id preference note added to `nextjs-add-auth` Security Rules
- **IM8 AS-8**: Secrets vault note added to all four scaffold generated `AGENTS.md` templates
- **IM8 AS-12**: File upload malware scanning note added to root `AGENTS.md`
- **IM8 LM-1**: Log isolation requirement added to `shared-add-logging` Production Requirement section

### Changed
- **NestJS scaffold**: Migrated from Jest to Vitest (NestJS 11 default); explicit `vitest.config.ts` + `vitest.config.e2e.ts`; `package.json` scripts now specified verbatim
- **NestJS scaffold**: Health endpoint response standardised to lowercase `{ status: 'ok' }` (matches all other stacks)
- **Both scaffolds**: `.dockerignore` trimmed from ~170 lines to ~60 essential patterns
- **Next.js scaffold**: Duplicate health route verbatim blocks consolidated
- **Vite+React scaffold**: Pinned `@vitejs/plugin-react@^6.0.0` (Oxc-based transforms) and bumped `react-router` floor to `^7.15.0` (stable API release)

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

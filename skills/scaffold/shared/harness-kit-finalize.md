<!-- ref: scaffold/shared/harness-kit-finalize.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table), the stack's variant file, and harness-kit-enforcement.md loaded; Steps A–B5 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — governance, manifest, and post-scaffold (Steps C–H)

Every stack. Step order and the delta table are in `harness-kit.md`.

---

## Step C. Create `FUTURE.md`

Create `FUTURE.md` at the project root:

**`FUTURE.md`**:
```markdown
# Future Directions

Design seams built into this project for AI collaboration patterns that are not yet activated. These are integration points, not features — nothing here runs unless you build it.

## Meta-Harness

CI that validates this project's own harness: a job that scaffolds the project and asserts the output passes tests and lint. Most near-term post-harness direction.

**Seam:** `<!-- [[post-harness:meta]] -->` in `AGENTS.md` — reserved for meta-harness CI configuration.

## Trace-Driven Evolution

Capture agent decision traces across sessions, aggregate patterns, and use them to improve conventions over time. Off by default.

**Seam:** None yet — no trace hook exists in the seeded `.claude/settings.json` (it is comment-free JSON with no disabled/placeholder entries). This is a roadmap item: a future revision could add a dedicated hook (e.g. a `Stop` or `SessionEnd` trace-writer) once a concrete consumer for the captured traces is designed. Until then, treat this as unactivated design intent, not an existing seam.

## Environment Engineering

A fully specified, reproducible environment ensuring every agent session starts from the same known state. Think devcontainers or Nix flakes with agent-specific overlays.

**Seam:** `devcontainer.json` if present.

---

*Seams from [templateCentral](https://github.com/cljiahao/templatecentral). None activated.*
```

---

## Step D. Seed `docs/CONSTITUTION.md`

Create `docs/CONSTITUTION.md` as the binding invariants document for this project.
It takes precedence over `AGENTS.md` and all skill guidance when there is a conflict.
Fill in the `[...]` placeholders with the actual project values.
Use the **quality-gate line** from the per-stack delta table in §6 Behavioural rules.

**`docs/CONSTITUTION.md`**:
```markdown
# CONSTITUTION.md

## 1. Purpose

This document defines the non-negotiable invariants for **[Project Name]**.
It applies to all contributors — human and AI agent alike. When `AGENTS.md`,
templateCentral skills, or any other guidance conflicts with this document,
**this document wins**. No PR may be merged that violates these rules without
an explicit `## Human Approval Override` section in the PR description.

## 2. Architecture Invariants

[Define the load-bearing architectural rules: layering, module boundaries,
factory/composition-root patterns, forbidden cross-imports, etc.]

## 3. Security Invariants

- Secrets NEVER appear in code, git, logs, or build output — use environment
  variables loaded from a secrets manager.
- All API routes authenticate before executing business logic.
- All mutations write to an audit log.

## 4. Testing Invariants

- New services must have integration tests (success, error, at least one edge case).
- New API routes must have route tests covering 401, 200, and at least one error path.
- CI must stay green — no PR may be merged with failing tests.

## 5. Git & PR Invariants

- Branch from `main`. Protected branches (`main`, `uat`, `develop`) — no direct commits.
- Every PR to `uat` and `main` requires the PR template fully filled.

## 6. Agent Governance Rules

### Protected files — human approval required

The following files require explicit human approval noted in the PR under
`## Protected File Changes`. Agents MUST NOT modify them without approval.

- `AGENTS.md` / `CLAUDE.md` — agent instruction files
- `docs/CONSTITUTION.md` — this document
- `.claude/settings.json` — harness wiring
- `.claude/hooks/*` — enforcement hooks
- `Dockerfile`
[Add project-specific protected files here]

### Behavioural rules

- Run the quality gate (see delta table for stack-specific command) before declaring any task done.
- Never use `--no-verify` on commits — this bypasses pre-commit hooks.
- Work on a feature branch — never commit directly to `main`, `uat`, or `develop`.
```

---

## Step E. Create `.claude/harness.json`

**Prerequisites:** Run this step only after the verify skills (and `next-migrate` for nextjs) have been created in `.claude/skills/` — these are seeded by the stack file's verify-skill step (6c for fastapi/nestjs/nextjs, 7c for vite-react), which runs between the kit's Steps D and E. Do not run Step E before that step.

Compute SHA-256 hashes and write `.claude/harness.json`. CLAUDE.md is created in a later optional step — hash it conditionally.

```bash
# Portable SHA-256: macOS ships shasum, minimal Linux images ship sha256sum.
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1; }
sha256_agents=$(sha256 AGENTS.md)   # provisional — Step G appends the tail + formats, then re-hashes
# Every enforcement hook script is a high-value tamper target — hash each for drift detection.
# Add a seeded_files entry (origin_hash + path) for EACH line printed below, alongside the core files:
for h in .claude/hooks/*; do printf '%s  %s\n' "$(sha256 "$h")" "$h"; done
# CLAUDE.md is optional (Step G) — hash it only if it already exists
[ -f CLAUDE.md ] && sha256_claude=$(sha256 CLAUDE.md)
sha256_settings=$(sha256 .claude/settings.json)
# Hash the verify skill (substitute `<stack>-verify` with the verify-skill name from the delta table, e.g. `next-verify` for nextjs):
sha256_verify=$(sha256 .claude/skills/<stack>-verify/SKILL.md)
sha256_skillaudit=$(sha256 .claude/skills/skill-audit/SKILL.md)
# nextjs only — hash the migrate skill too (file-existence guard makes this a no-op on other stacks):
[ -f .claude/skills/next-migrate/SKILL.md ] && sha256_migrate=$(sha256 .claude/skills/next-migrate/SKILL.md)
# Git-hook layer (Step B2) — drift-tracked too:
sha256_lefthook=$(sha256 lefthook.yml)
sha256_commitmsg=$(sha256 .lefthook/commit-msg.sh)
sha256_gitleaks=$(sha256 .gitleaks.toml)
sha256_comment_patterns=$(sha256 .claude/comment-hygiene-patterns.txt)
sha256_ci=$(sha256 .github/workflows/ci.yml)
sha256_verifyh=$(sha256 .claude/verify-harness.sh)
sha256_regenh=$(sha256 .claude/regen-harness.sh)
```

**`.claude/harness.json`** (substitute stack name, verify-skill path, and computed hashes):
```json
{
  "templatecentral_version": "5.21.0",
  "stack": "<stack>",
  "seeded_at": "<ISO-date>",
  "seeded_files": {
    "AGENTS.md": { "origin_hash": "<sha256_agents>", "path": "AGENTS.md" },
    "CLAUDE.md": { "origin_hash": "<sha256_claude>", "path": "CLAUDE.md" },
    ".claude/settings.json": { "origin_hash": "<sha256_settings>", "path": ".claude/settings.json" },
    ".claude/skills/<stack>-verify/SKILL.md": { "origin_hash": "<sha256_verify>", "path": ".claude/skills/<stack>-verify/SKILL.md" },
    ".claude/skills/skill-audit/SKILL.md": { "origin_hash": "<sha256_skillaudit>", "path": ".claude/skills/skill-audit/SKILL.md" },
    ".claude/hooks/protect-files.sh": { "origin_hash": "<sha256_hook_1>", "path": ".claude/hooks/protect-files.sh" },
    ".claude/hooks/block-no-verify.sh": { "origin_hash": "<sha256_hook_2>", "path": ".claude/hooks/block-no-verify.sh" },
    ".claude/hooks/user-prompt-guard.<ext>": { "origin_hash": "<sha256_hook_3>", "path": ".claude/hooks/user-prompt-guard.<ext>" },
    ".claude/hooks/post-edit-typecheck.sh": { "origin_hash": "<sha256_hook_4>", "path": ".claude/hooks/post-edit-typecheck.sh" },
    ".claude/hooks/stop-checks.sh": { "origin_hash": "<sha256_hook_5>", "path": ".claude/hooks/stop-checks.sh" },
    ".claude/hooks/subagent-stop.sh": { "origin_hash": "<sha256_hook_6>", "path": ".claude/hooks/subagent-stop.sh" },
    ".claude/hooks/session-context.sh": { "origin_hash": "<sha256_hook_7>", "path": ".claude/hooks/session-context.sh" },
    ".claude/hooks/skill-usage-log.sh": { "origin_hash": "<sha256_hook_8>", "path": ".claude/hooks/skill-usage-log.sh" },
    ".claude/hooks/post-edit-comment-check.sh": { "origin_hash": "<sha256_hook_9>", "path": ".claude/hooks/post-edit-comment-check.sh" },
    "lefthook.yml": { "origin_hash": "<sha256_lefthook>", "path": "lefthook.yml" },
    ".lefthook/commit-msg.sh": { "origin_hash": "<sha256_commitmsg>", "path": ".lefthook/commit-msg.sh" },
    ".gitleaks.toml": { "origin_hash": "<sha256_gitleaks>", "path": ".gitleaks.toml" },
    ".claude/comment-hygiene-patterns.txt": { "origin_hash": "<sha256_comment_patterns>", "path": ".claude/comment-hygiene-patterns.txt" },
    ".github/workflows/ci.yml": { "origin_hash": "<sha256_ci>", "path": ".github/workflows/ci.yml" },
    ".claude/verify-harness.sh": { "origin_hash": "<sha256_verifyh>", "path": ".claude/verify-harness.sh" },
    ".claude/regen-harness.sh": { "origin_hash": "<sha256_regenh>", "path": ".claude/regen-harness.sh" }
  }
}
```

> `user-prompt-guard.<ext>` is `.cjs` for TS stacks (nestjs, nextjs, vite-react) and `.py` for FastAPI. The kit seeds **9** hook scripts — one `seeded_files` entry each (`<sha256_hook_1>`…`<sha256_hook_9>`); `verify-harness.sh` exits 2 while any `<…>` placeholder remains.
> The `AGENTS.md` (and `CLAUDE.md`) hashes written here are provisional: Step G appends the AGENTS.md tail and runs the final format pass, then re-hashes every entry and refreshes `.claude/.harness-base/`.
> Omit the `CLAUDE.md` entry if `CLAUDE.md` does not exist yet — it is created in Step G (optional). If you create it there, append its entry to `seeded_files` with the hash at that point.
> For **nextjs**, also add a `".claude/skills/next-migrate/SKILL.md"` entry.

---

## Step E2. Seed the base snapshot (enables safe day-2 re-sync)

Copy every seeded file into `.claude/.harness-base/` — a committed snapshot of the **as-seeded** content. This is the merge *base* that `templatecentral:migrate` Phase 5 uses to **3-way-merge** harness updates into the project without clobbering the user's edits (templateCentral can't re-render an old version like cruft/copier, so the base is snapshotted at seed time).

```bash
mkdir -p .claude/.harness-base
# Mirror each seeded path into .claude/.harness-base/ (same relative path). Paths come from the manifest just written.
for p in $(python3 -c "import json;[print(v['path']) for v in json.load(open('.claude/harness.json'))['seeded_files'].values()]" 2>/dev/null \
          || node -e 'const m=require("./.claude/harness.json");for(const v of Object.values(m.seeded_files))console.log(v.path)'); do
  [ -f "$p" ] || continue
  mkdir -p ".claude/.harness-base/$(dirname "$p")"
  cp "$p" ".claude/.harness-base/$p"
done
```

**Commit** `.claude/.harness-base/` — it travels with the repo so collaborators and CI share the same merge base. It is tamper-protected by `protect-files.sh` (editing the base would poison a future re-sync merge); the harness verifier ignores it (it is the base, not a live enforcement file).

---

## Step E3. Generate per-folder documentation

Seed the structural per-folder README convention (and, if the project opts in, Azure DevOps Code Wiki `.order` files) now that every source file, harness file, and project skill exists on disk:

```bash
cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
```

Follow it exactly — it determines the ADO Code Wiki and rich-content opt-ins (each asked once, then persisted in `.claude/harness.json`), enumerates every folder in the project, and writes or refreshes each folder's `README.md` (and `.order` files, if opted in).

---

## Step F. Create `.agents` symlink

Create the cross-vendor symlink so the project works with any agent framework that resolves from `.agents/`:

```bash
ln -s .claude .agents
```

This makes `AGENTS.md`, `settings.json`, `rules/`, `skills/`, and `hooks/` discoverable by Claude Code (`.claude/`) and any other tool that looks in `.agents/` — one source of truth, zero duplication.

**Never commit the symlink** — the scaffold's `.gitignore` already lists `.agents`; verify the entry exists (add it if migrating an older project). A git-tracked symlink breaks Windows CI build agents (e.g. "Unable to load symbolic/hard linked file" on Azure DevOps hosted runners). The symlink is per-machine convenience; recreate it locally (or via a postinstall script) instead of tracking it.

---

## Step G. Post-scaffold agent workflow

**AGENTS.md tail — always appended, single source:** None of the four stack templates or the two migrate templates embed the `## AI Harness` / `## Skills Security` / `## Git Workflow` / `## Skill capture` tail — it is intentionally omitted from every one of them so this step is the *only* place it comes from. After the stack-specific AGENTS.md template body is written, unconditionally append the shared tail fragment below, substituting the `PostToolUse` line's `(see delta table for stack command)` placeholder with the current stack's **Typecheck feedback cmd** from the Per-stack delta table. Do this every time — for a fresh scaffold and for a migrate re-seed — so the tail can never drift out of sync with what's actually shipped: there is exactly one copy of this text in the whole repo (below), and every AGENTS.md gets it fresh from here.

**Final format pass (TS stacks only — run before the utilities below):** every source/config file was formatted once early in the scaffold flow, but `FUTURE.md`, `docs/CONSTITUTION.md` (Steps C/D), every per-folder `README.md` (Step E3), and the AGENTS.md tail just appended above were all written *after* that pass — an untouched, byte-for-byte-correct scaffold otherwise fails its own `pnpm run check` (and CI's `quality` job) on files nobody edited. Run `pnpm exec prettier --write .` once now, over the whole project, before continuing. (FastAPI: not needed — `ruff format`/`ruff check` only ever touch `*.py`, and README/CONSTITUTION/FUTURE content is never `.py`.)

**Re-baseline the manifest (all stacks — after the tail append and the format pass, before the utilities below):** Step E hashed `AGENTS.md` before this step appended its tail, and the format pass may have rewritten other seeded files, so recompute every `origin_hash` from the files as they now stand and refresh the base snapshot. This is part of seeding, not a drift blessing — it runs once, here, before the first commit:
```bash
if command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs"),cr=require("crypto"),f=".claude/harness.json",j=JSON.parse(fs.readFileSync(f,"utf8"));for(const v of Object.values(j.seeded_files)){if(fs.existsSync(v.path))v.origin_hash=cr.createHash("sha256").update(fs.readFileSync(v.path)).digest("hex");}fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")'
else
  python3 -c 'import json,hashlib,os;f=".claude/harness.json";j=json.load(open(f));[v.__setitem__("origin_hash",hashlib.sha256(open(v["path"],"rb").read()).hexdigest()) for v in j["seeded_files"].values() if os.path.isfile(v["path"])];open(f,"w").write(json.dumps(j,indent=2)+"\n")'
fi
# Refresh the Step E2 base snapshot so .claude/.harness-base/ mirrors the final bytes, then confirm:
for p in $(python3 -c "import json;[print(v['path']) for v in json.load(open('.claude/harness.json'))['seeded_files'].values()]" 2>/dev/null \
          || node -e 'const m=require("./.claude/harness.json");for(const v of Object.values(m.seeded_files))console.log(v.path)'); do
  [ -f "$p" ] || continue
  mkdir -p ".claude/.harness-base/$(dirname "$p")"
  cp "$p" ".claude/.harness-base/$p"
done
bash .claude/verify-harness.sh
```
If `CLAUDE.md` is created in this step, add its `seeded_files` entry before running the re-baseline.

After the stack-specific AGENTS.md is written (with the shared tail fragment appended per above), the final format pass, and the re-baseline above, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — verify the scaffold compiles clean
2. the test utility — load it with: `cat "<skill-dir>/../test/SKILL.md"` — verify all scaffold tests pass
3. the review utility (update operation) — load it with: `cat "<skill-dir>/../review/SKILL.md"` — freshen any deps that have newer compatible versions
4. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip these steps if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

---

## Step H. Install Claude Code plugins

**Claude Code users only.** Register the marketplaces, then install the plugins from them — `marketplace add` only registers a source, it does not install anything. These are **on by default** — skip only if the user explicitly opts out. Plugin installs are user-scoped, not project-directory-scoped.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman
claude plugin marketplace add obra/superpowers
claude plugin install superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

---

## Shared AGENTS.md tail fragment

**Append this below the stack-specific AGENTS.md template** (after the stack's Rules section, before the closing line if any):

```markdown
## AI Harness
PreToolUse (Edit/Write/NotebookEdit): blocks secrets and CI pipeline files only (exit 2): `.env*` (except `.env.example`), CI/CD definitions (`.github/workflows/`, `.github/actions/`, `.azuredevops/`, `azure-pipelines*.y[a]ml`, `.gitlab-ci.yml`, `Jenkinsfile`), cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`; a second Bash guard blocks `--no-verify`, hook-layer bypasses (`LEFTHOOK=0`, `git -c core.hooksPath=…`, `git config core.hooksPath`), commits to protected branches, and force-pushes to them (incl. `--force-with-lease`, `HEAD:main`). Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/clear/compact): re-injects AGENTS.md routing context + universal invariants so they survive compaction (PostCompact stdout is also injected as context and fires after compaction, but SessionStart additionally covers resume/startup, so it's the seeded mechanism here).
UserPromptSubmit: pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.
PostToolUse: incremental type-check (see delta table for stack command) and a comment-hygiene scan (change-narration comments, oversized comment blocks — patterns from `.claude/comment-hygiene-patterns.txt`) after every Edit/Write. Both feedback-only — findings reach Claude as `additionalContext`, never a block.
Stop hook: runs the full test suite when there are uncommitted changes; exit 2 feeds failures to Claude via stderr; exit 0 on pass (Claude Code caps consecutive Stop continuations — 8 by default). SubagentStop: type-gates a subagent's uncommitted changes (read-only Explore/Plan agents skipped).
Hook wiring: every `settings.json` hook is `"command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>"]` — an array-valued `command` is silently ignored by Claude Code.
Git hooks (lefthook): pre-commit runs format/lint/typecheck + gitleaks secret-scan on staged files, plus a readme-coupling staleness warning and a comment-hygiene warning; commit-msg enforces Conventional Commits; pre-push runs the quality gate. Hard-local; coverage/changed-line/comment-hygiene gates run in CI.
CI (GitHub Actions): hard gate on changed-line coverage (`diff-cover` ≥80%), lockfile-in-sync (`--frozen-lockfile`), a changelog-touched check, a readme-freshness check, a comment-hygiene check on added lines (bypassable via `skip-comment-check` label), and a gitleaks secret scan (the PR's commits; full history on push to `main`) via the checksum-verified MIT CLI.
Project skills: `.claude/skills/` | Manifest: `.claude/harness.json`
Context load order (context only — not enforcement, broad → specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → this file → `.claude/rules/*.md` (lazy per-directory). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security
- Review `SKILL.md` content before installing any third-party skill — treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (e.g. `Bash(git *)` not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Git Workflow

**Branch source:** Always fork from an up-to-date `main`.
Before branching: `git fetch -p` then update `main` (`git checkout main && git pull --ff-only`). Fork the feature FROM the freshly-pulled `main`.

(The seeded hooks separately protect the common branch names `main`/`uat`/`develop` from direct commits and force-push regardless of which PR route you use — see "AI Harness" above. That protection is a fixed baseline safety net independent of the route table below; it is not "the route" this repo follows, just names the hooks always guard.)

<!-- Per-repo: below this line, document the protected-branch route table for THIS deployment (e.g. develop/uat, develop/staging/live, or trunk). The fetch-first step above is universal; the route clause is not. -->

## Skill capture
- A workflow done twice → author a `.claude/skills/<name>/` project skill and commit it, so the repo (and teammates) carry it, not just session memory. `/skill-audit` surfaces repeats from `.claude/skill-usage.log`.
- Don't vendor third-party plugin skills — re-author the workflow as a project skill tuned to this repo.
```

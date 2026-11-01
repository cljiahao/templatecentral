<!-- ref: scaffold/shared/harness-kit-finalize.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table), the stack's variant file, and harness-kit-enforcement.md loaded; Steps A–B5 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — governance, manifest, and post-scaffold (Steps C–H)

Every stack. Step order and the delta table are in `harness-kit.md`.

---

## Step C. Seed `FUTURE.md`, `docs/CONSTITUTION.md` and the `/skill-audit` skill

Run `tc-copy.sh` of `harness-kit.md` Step 0 as `TC_STACK=<stack> TC_PART=late bash "<skill-dir>/shared/tc-copy.sh" "<target>"` with the `STACK` of Step 0, after the stack's verification gate and its format pass. It copies three files from `<skill-dir>/shared/template-late/` and refuses when any already exists:

- `FUTURE.md` — design seams for AI collaboration patterns not yet activated.
- `docs/CONSTITUTION.md` — binding invariants; wins over `AGENTS.md` and all skill guidance.
- `.claude/skills/skill-audit/SKILL.md` — the Step B5 skill.

---

## Step D. Fill in `docs/CONSTITUTION.md`

With the Edit tool, replace `__TC_PROJECT_TITLE__` in `docs/CONSTITUTION.md` with the project title. The title must be a single line: if it holds a newline, stop and ask the user for a one-line title and edit nothing. Fill in the other `[...]` placeholders (Architecture Invariants, project-specific protected files) with the actual project values, and use the **quality-gate line** from the per-stack delta table in §6 Behavioural rules. Then check that no placeholder is left:

```bash
grep -n '__TC_' docs/CONSTITUTION.md
```

It must print nothing.

---

## Step E. Create `.claude/harness.json`

**Prerequisites:** run only after the stack file's verify-skill step (6c for fastapi/nestjs/nextjs, 7c for vite-react) has created the verify skills (and `next-migrate` for nextjs).

Compute SHA-256 hashes and write `.claude/harness.json`. Hash `CLAUDE.md` only if it exists.

```bash
# Portable SHA-256: macOS ships shasum, minimal Linux images ship sha256sum.
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1; }
sha256_agents=$(sha256 AGENTS.md)   # provisional — Step G appends the tail + formats, then re-hashes
# Every enforcement hook script is a high-value tamper target — hash each for drift detection.
# Add a seeded_files entry (origin_hash + path) for EACH line printed below, alongside the core files:
for h in .claude/hooks/* .claude/hooks/local/*; do [ -f "$h" ] && printf '%s  %s\n' "$(sha256 "$h")" "$h"; done
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
# CI (Step B3) — the one file seeded for this host, plus the shared gate script:
[ -f .github/workflows/ci.yml ] && sha256_ci=$(sha256 .github/workflows/ci.yml)
[ -f azure-pipelines/templatecentral-gates.yml ] && sha256_ci=$(sha256 azure-pipelines/templatecentral-gates.yml)
[ -f .claude/ci-gates.sh ] && sha256_cigates=$(sha256 .claude/ci-gates.sh)
sha256_verifyh=$(sha256 .claude/verify-harness.sh)
sha256_regenh=$(sha256 .claude/regen-harness.sh)
```

**`.claude/harness.json`** (substitute stack name, verify-skill path, and computed hashes):
```json
{
  "templatecentral_version": "7.2.0",
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
    ".claude/ci-gates.sh": { "origin_hash": "<sha256_cigates>", "path": ".claude/ci-gates.sh" },
    ".claude/verify-harness.sh": { "origin_hash": "<sha256_verifyh>", "path": ".claude/verify-harness.sh" },
    ".claude/regen-harness.sh": { "origin_hash": "<sha256_regenh>", "path": ".claude/regen-harness.sh" }
  }
}
```

> `user-prompt-guard.<ext>` is `.cjs` for TS stacks (nestjs, nextjs, vite-react) and `.py` for FastAPI. The kit seeds **9** hook scripts — one `seeded_files` entry each (`<sha256_hook_1>`…`<sha256_hook_9>`); `verify-harness.sh` exits 2 while any `<…>` placeholder remains.
> The `AGENTS.md` (and `CLAUDE.md`) hashes written here are provisional: Step G appends the AGENTS.md tail and runs the final format pass, then re-hashes every entry and refreshes `.claude/.harness-base/`.
> Omit the `CLAUDE.md` entry if it does not exist yet; Step G adds it if created there.
> For **nextjs**, also add a `".claude/skills/next-migrate/SKILL.md"` entry.
> On **Azure DevOps** (Step B3), key and path the CI entry as `azure-pipelines/templatecentral-gates.yml` instead of `.github/workflows/ci.yml` — or omit both CI entries and the `ci-gates.sh` entry when Step B3 seeded neither because the project's pipelines already cover them. Add one entry per `.claude/hooks/local/*` script the loop above prints.

---

## Step E2. Seed the base snapshot (enables safe day-2 re-sync)

Copy every seeded file into `.claude/.harness-base/` — a committed snapshot of the **as-seeded** content, the merge *base* `templatecentral:migrate` Phase 5 uses to **3-way-merge** harness updates without clobbering the user's edits.

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

**Commit** `.claude/.harness-base/`. `protect-files.sh` guards it; the harness verifier ignores it.

---

## Step E3. Generate per-folder documentation

Seed the per-folder README convention (and opt-in Azure DevOps Code Wiki `.order` files) now that every file exists:

```bash
cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
```

Follow it exactly.

---

## Step F. Create `.agents` symlink

Create the cross-vendor symlink for tools that resolve from `.agents/`:

```bash
ln -s .claude .agents
```

**Never commit the symlink** — verify `.gitignore` lists `.agents` (add it when migrating). A tracked symlink breaks Windows CI agents ("Unable to load symbolic/hard linked file" on Azure DevOps hosted runners).

---

## Step G. Post-scaffold agent workflow

**AGENTS.md tail — always appended, single source:** the `## AI Harness` / `## Skills Security` / `## Git Workflow` / `## Skill capture` tail comes only from this step. After the stack-specific AGENTS.md is written, append it unconditionally, for a fresh scaffold and a migrate re-seed. The tail is the real file `<skill-dir>/shared/template-tail/AGENTS-tail.md`, which the script reads (a migration runs `<skill-dir>/../scaffold/shared/tc-copy.sh`: change only that path). `TC_PART=tail` builds the whole text first, so a failure appends nothing, and refuses when `<target>/AGENTS.md` does not exist. The typecheck command that replaces the marker `see delta table for stack command` (inside its parentheses) is fixed per stack inside the script; only `STACK` is yours to set:

```bash
TC_STACK=<stack> TC_PART=tail bash "<skill-dir>/shared/tc-copy.sh" "<target>"
```

**Final format pass (TS stacks only — run before the utilities below):** Steps C/D, E3 and the tail wrote files after the first format pass, so run `pnpm format` once now (the project script formats exactly what `pnpm run check` checks), or `pnpm run check` and CI's `quality` job fail on files nobody edited. (FastAPI: not needed — ruff touches only `*.py`.)

**Re-baseline the manifest (all stacks — after the tail append and the format pass, before the utilities below):** the tail and the format pass changed seeded files, so recompute every `origin_hash` and refresh the base snapshot. Part of seeding, not a drift blessing — once, before the first commit:
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

Then run these agent skills in order. They are **on by default** — skipping requires explicit user confirmation.

1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — verify the scaffold compiles clean
2. the test utility — load it with: `cat "<skill-dir>/../test/SKILL.md"` — verify all scaffold tests pass
3. the review utility (update operation) — load it with: `cat "<skill-dir>/../review/SKILL.md"` — freshen any deps that have newer compatible versions
4. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip these steps if the user confirms.

**If any agent reports failures:** Stop there and do not run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

---

## Step H. Install Claude Code plugins

**Claude Code users only.** `marketplace add` only registers a source; then install. **On by default** — skip only if the user opts out. Installs are user-scoped.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman
claude plugin marketplace add obra/superpowers
claude plugin install superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

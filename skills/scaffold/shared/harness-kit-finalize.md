<!-- ref: scaffold/shared/harness-kit-finalize.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table), the stack's variant file, and harness-kit-enforcement.md loaded; Steps A–B5 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — governance, manifest, and post-scaffold (Steps C–H)

Every stack. Step order and the delta table are in `harness-kit.md`.

---

## Step C. Seed `FUTURE.md`, `docs/CONSTITUTION.md`, `docs/harness.md` and the `/skill-audit` skill

Run `tc-copy.sh` of `harness-kit.md` Step 0 as `TC_STACK=<stack> TC_PART=late bash "<skill-dir>/shared/tc-copy.sh" "<target>"` with the `STACK` of Step 0, after the stack's verification gate and its format pass. It copies four files from `<skill-dir>/shared/template-late/` and refuses when any already exists:

- `FUTURE.md` — design seams for AI collaboration patterns not yet activated.
- `docs/CONSTITUTION.md` — binding invariants; wins over `AGENTS.md` and all skill guidance.
- `docs/harness.md` — the reference detail behind the short `## AI Harness` / `## Git Workflow` tail of Step G, which points to it.
- `.claude/skills/skill-audit/SKILL.md` — the Step B5 skill.

---

## Step D. Fill in `docs/CONSTITUTION.md`

With the Edit tool, replace `__TC_PROJECT_TITLE__` in `docs/CONSTITUTION.md` with the project title. The title must be a single line: if it holds a newline, stop and ask the user for a one-line title and edit nothing. Replace each `[Fill in: …]` line with the project's real value, or delete it where it says so. The §6 quality gate is the **quality-gate line** from the per-stack delta table. Then check that no placeholder is left:

```bash
grep -nE '__TC_|\[Fill in' docs/CONSTITUTION.md
```

It must print nothing.

---

## Step E. Create `.claude/harness.json`

**Prerequisites:** run only after the stack file's verify-skill step (6c for fastapi/nestjs/nextjs, 7c for vite-react) has created the verify skills (and `next-migrate` for nextjs).

Write `.claude/harness.json` with the copy script. It hashes every seeded file present (`AGENTS.md`, `CLAUDE.md` if the stack's CLAUDE.md step created it, `settings.json`, the verify skills of the delta table, `/skill-audit`, every file under `.claude/hooks/` including `local/`, the git-hook layer, the CI files Step B3 seeded and the harness scripts), takes `templatecentral_version` from the plugin's `.claude-plugin/plugin.json`, and refuses when the file already exists or a verify skill is missing:

```bash
TC_STACK=<stack> TC_PART=manifest TC_ADO_WIKI=<true|false> TC_RICH_README=<true|false> bash "<skill-dir>/shared/tc-copy.sh" "<target>"
```

`TC_ADO_WIKI` and `TC_RICH_README` are the Step E3 documentation choices (both default to `false`). In a scaffold, set them from the scaffold Step 1 answers on the Azure DevOps Code Wiki (`adoWiki`) and rich READMEs (`richReadme`), so Step E3 reads them and asks nothing. A migration has no scaffold Step 1: reuse the `adoWiki` and `richReadme` values of the project's previous manifest when it has them, and otherwise ask the user both questions, worded as in `documentation-kit.md` Steps 1a and 1b, before running the script. They become the top-level `adoWiki` and `richReadme` fields that `documentation-kit.md` reads. The `AGENTS.md` and `CLAUDE.md` hashes are provisional: Step G appends the AGENTS.md tail and runs the final format pass, then re-hashes every entry and refreshes `.claude/.harness-base/`. A file seeded later (a hook added to `.claude/hooks/local/`) gets its own `seeded_files` entry in the same `{ "origin_hash": …, "path": … }` shape.

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

Keep `.claude/.harness-base/` tracked: it goes in with the project's first commit. `protect-files.sh` guards it; the harness verifier ignores it.

---

## Step E3. Generate per-folder documentation

Seed the per-folder README convention (and opt-in Azure DevOps Code Wiki `.order` files) now that every file exists:

```bash
cat "<skill-dir>/shared/documentation-kit.md"   # migrate: <skill-dir>/../scaffold/shared/documentation-kit.md
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

**AGENTS.md tail — managed block, single source:** the `## AI Harness` / `## Skills Security` / `## Git Workflow` / `## Skill capture` tail comes only from this step. After the stack-specific AGENTS.md is written, `TC_PART=tail` writes it between the `<!-- BEGIN:templatecentral-tail … -->` and `<!-- END:templatecentral-tail -->` lines, for a fresh scaffold and a migrate re-seed. No markers and no `## AI Harness` / `## Harness` heading: it appends the wrapped tail. Exactly one marker pair: it replaces everything between them (markers included) and leaves every other byte alone, so a re-run adds no second copy. Malformed markers (one, a duplicate, END before BEGIN), or no markers but a harness heading: it stops with an error and writes nothing; in the heading case, wrap the existing generic tail in the two marker lines by hand first. Repo rules go outside the markers. The tail is the real file `<skill-dir>/shared/template-tail/AGENTS-tail.md`, which the script reads (a migration runs `<skill-dir>/../scaffold/shared/tc-copy.sh`: change only that path). `TC_PART=tail` builds the whole text first, so a failure writes nothing (a replace goes through a temp file beside AGENTS.md and a `mv`, so AGENTS.md is never left half-written), and refuses when `<target>/AGENTS.md` does not exist. The typecheck command that replaces the marker `see delta table for stack command` (inside its parentheses) is fixed per stack inside the script; only `STACK` is yours to set:

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
2. the test utility — load it with: `cat "<skill-dir>/../test/SKILL.md"` — run the existing suite and confirm it passes. At scaffold time it writes no new tests and does not load `templatecentral:add (test)`: the template's tests already cover the copied code.
3. the review utility (update operation) — load it with: `cat "<skill-dir>/../review/SKILL.md"` — freshen any deps that have newer compatible versions
4. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — review only the files the agent edited by hand during the scaffold: the stack guide's Step 1 and Step 2 edits (project name, branding, settings), the filled-in `docs/CONSTITUTION.md` and the generated READMEs. The copied templates are not in scope; they are reviewed when the plugin is released. The project has no commit yet, so this review writes no `.claude/review-baseline.md`; the first review after the project's first commit writes it.

**Skipping these steps:** use the scaffold Step 1 answer on post-scaffold checks. If the user asks to skip and has not already confirmed it, warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip these steps if the user confirms.

**If any agent reports failures:** Stop there and do not run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

---

## Step H. Install Claude Code plugins

**Claude Code users only.** `marketplace add` only registers a source; then install. **On by default** — use the scaffold Step 1 answer on Claude Code plugins, and skip only if the user opted out there or opts out now. Installs are user-scoped.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman
claude plugin marketplace add obra/superpowers
claude plugin install superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

**No interactive user** (headless run): skip this step unless the run's instructions say to install the plugins, and note the skip in your final report. An unattended run does not change user-scoped Claude Code configuration on its own.

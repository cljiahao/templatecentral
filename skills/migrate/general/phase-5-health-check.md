<!-- ref: migrate/general/phase-5-health-check.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Phase 0 of migrate/general/implementation.md routed here (project at @6.0.0+ with .claude/harness.json, or the @5.x hook re-sync). Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate — Phase 5 (harness health check + safe re-sync)

Phase 4 (full seed) is `phase-4-upgrade.md`.

---

## Phase 5 — Harness Health Check

Run when line 1 has `<!-- templateCentral: <stack>@6.0.0 -->` **and** `.claude/harness.json` exists, or for a `@5.x` hook re-sync. Reports drift from the origin hashes; never auto-repairs.

**Step 5a: Read `.claude/harness.json`**

Read the `seeded_files` map.

**Step 5b: Check each seeded file**

For each entry in `seeded_files`:

```bash
# Same portable helper as harness-kit Step E: macOS ships shasum, minimal Linux images ship sha256sum.
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1; }
current_hash=$(sha256 <path> 2>/dev/null)
```

Compare `current_hash` to `origin_hash`. Classify each file:

- `UNCHANGED` — hashes match
- `MODIFIED` — hashes differ (user or agent edited it)
- `MISSING` — file does not exist

**Step 5c: Report**

In the header, `<version>` is the plugin release, read from `.claude-plugin/plugin.json` (`version`) in the plugin directory.

```
Harness health check — templateCentral <version> / <stack>
Seeded: <seeded_at>

  AGENTS.md              UNCHANGED
  CLAUDE.md              MODIFIED   ← you customized this
  .claude/settings.json  UNCHANGED

MODIFIED files are intentional edits. To pull the latest templateCentral defaults
into them WITHOUT losing your edits, run the safe re-sync (Step 5d) — it 3-way-merges,
it does not clobber.
```

If all files are `UNCHANGED`, `templatecentral_version` equals the current plugin version **and** the `AGENTS.md` import is present, print:
```
✓ All harness files match their templateCentral origin and are up to date. No action needed.
```

If `CLAUDE.md` lacks the import (rule in `phase-4-upgrade.md` Step 4c), warn; Step 5d offers the fix:
```
⚠ CLAUDE.md does not import AGENTS.md. Claude Code loads AGENTS.md only through an `@AGENTS.md` line in CLAUDE.md.
  Step 5d can append it on approval.
```

If any file is `MISSING`, print a warning:
```
⚠ <path> is missing. This may cause templateCentral skills to behave unexpectedly.
  Re-seed it via the re-sync below (Step 5d).
```

**Step 5d: Safe re-sync (3-way merge) ⛔ GATE**

Canonical content comes from the template files (`phase-4-upgrade.md` Step 4d) and the harness kit loaded by `implementation.md`.

Offer this when there is something to apply: a `MODIFIED`/`MISSING` file, a missing `AGENTS.md` import, or a `harness.json.templatecentral_version` older than the plugin. **Never write without explicit user approval.** Present a dry-run plan (per file: action + diff preview), then on approval apply per **file class**:

- **Enforcement layer** (`.claude/hooks/*` except `local/`, `.claude/comment-hygiene-patterns.txt`, `lefthook.yml`, `.lefthook/*`, `.gitleaks.toml`, `.claude/ci-gates.sh`, the host's CI file, `.claude/verify-harness.sh`, `.claude/regen-harness.sh`): these are not meant to be hand-edited (the verifier flags them), and a re-sync resets them to canonical. **Overwrite** file by file (never a bulk `cp -R`) with the canonical file from `<skill-dir>/../scaffold/shared/template/`, `template-ts/` or `template-py/`, or `template-ci/` for the CI file, as `<skill-dir>/../scaffold/shared/template.manifest` lists. The `TC_PART=ci` runs of the copy script are scaffold-only; re-sync the CI file by hand under the same rules. `protect-files.sh` asks per write, so show these diffs in the dry-run plan. If one was `MODIFIED`, warn, and check whether a `templatecentral:add` capability extended it (e.g. `add (redaction)` in `user-prompt-guard`); if so, name the capability to re-apply. Any other local edit to a canonical hook moves into a `.claude/hooks/local/` script with its own `settings.json` entry (kit Step A, "Project-local guards") in the same re-sync, so the rule survives.
- **User-co-owned** (`AGENTS.md`, `CLAUDE.md`, `.claude/skills/<stack>-verify/SKILL.md`, `.claude/skills/skill-audit/SKILL.md`, nextjs `next-migrate`):
  - `UNCHANGED` → overwrite with the new canonical.
  - `MODIFIED` → **3-way merge** against the base snapshot:
    ```bash
    f="<seeded path>"                       # not `path`: zsh ties $path to $PATH
    PLUGIN_VER="<current plugin.json version>"
    base=".claude/.harness-base/$f"         # the as-seeded content
    new="$(mktemp)"                          # write the CURRENT canonical content for $f here
    if [ -f "$base" ]; then
      cp "$f" "$f.merging"
      git merge-file -L "your version" -L "seeded base" -L "templateCentral $PLUGIN_VER" \
        "$f.merging" "$base" "$new"
      rc=$?; mv "$f.merging" "$f"
      [ $rc -ne 0 ] && echo "⚠ $f: merge conflicts — resolve the <<<<<<< markers, then re-run verify."
    else
      echo "No base snapshot for $f (project predates .harness-base). Showing a diff for MANUAL merge — not overwriting:"
      diff -u "$f" "$new" || true
    fi
    ```
    Conflict markers appear only where the user's edit and the upstream change overlap; resolve them by hand.
- **`.claude/settings.json`** (co-owned, JSON): do **not** raw-text-merge (a conflict marker breaks the JSON). Merge structurally: add new seeded `hooks`/`permissions.deny` entries without removing the user's. **Replace** (not keep alongside) any `.claude/hooks/` entry whose `command` is a JSON array or lacks `${CLAUDE_PROJECT_DIR}` (pre-6.0.0, never ran). Remove `Edit`/`Write` denies on CI or governance paths (`.claude/settings*.json`, `.claude/hooks/**`, `.github/workflows/**`, `azure-pipelines/**`): a deny outranks the hook's ask and blocks human-approved edits. Keep every entry pointing at `.claude/hooks/local/`. Remove the `PostToolUseFailure` → `post-tool-failure.sh` entry; list `.claude/hooks/post-tool-failure.sh` and its `harness.json` entry for deletion in the dry-run plan.
- `MISSING` → reseed (write the current canonical content).
- **Unwired Azure gates** — if no pipeline includes `azure-pipelines/templatecentral-gates.yml` (grep the pipeline YAML for `templatecentral-gates`) and the pipelines already run gitleaks, the harness check **and** a high/critical dependency audit: list it, `.claude/ci-gates.sh`, their `harness.json` entries and base copies for deletion, and drop the CI line's template wording from AGENTS.md. If any of the three checks is missing, wire it in instead (kit Step B3). Never list `.claude/ci-gates.sh` for deletion while the pipelines lack a dependency audit.
- **Azure pipelines without a dependency audit** — if they run gitleaks and the harness check but no high/critical dependency audit, and `.claude/ci-gates.sh` is absent or has no `deps` gate: list seeding it and adding a `bash .claude/ci-gates.sh deps` step in the dry-run plan (kit Step B3). The step needs `pnpm` or `uv` and `pipx` after the install steps; `protect-files.sh` asks the human first.

- **Missing `AGENTS.md` import** — if Step 5c flagged it, list the append whatever `CLAUDE.md`'s class. On approval append `@AGENTS.md` as `phase-4-upgrade.md` Step 4c does, touch no other line, and skip the 3-way merge for it (a merge would keep a deleted import). If `harness.json` tracks `CLAUDE.md`, count it as written below so its hash and base copy refresh; otherwise create neither.

**After applying** (only the files actually written):
```bash
# refresh the base snapshot to the new canonical content
for p in <files written>; do mkdir -p ".claude/.harness-base/$(dirname "$p")"; cp "$p" ".claude/.harness-base/$p"; done
# recompute origin_hash for each in harness.json, and bump templatecentral_version to "$PLUGIN_VER"
bash .claude/verify-harness.sh   # confirm the enforcement layer is clean post-sync
```

If a reseed created a new directory outside the paths documentation-kit.md Step 2 prunes (`.lefthook/` or `docs/` count; `.claude/`, `.github/` and secrets directories do not), re-run the documentation kit for it (loaded by the phase table in `implementation.md`).

Then re-run Step 5b/5c and confirm everything is `UNCHANGED` and up to date.

<!-- ref: migrate/general/phase-5-health-check.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Phase 0 of migrate/general/implementation.md routed here (project at @6.0.0+ with .claude/harness.json, or the @5.x hook re-sync). Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate — Phase 5 (harness health check + safe re-sync)

Loaded from `implementation.md` Phase 0. Phase 4 (full seed) is `phase-4-upgrade.md`.

---

## Phase 5 — Harness Health Check

Run when `templatecentral:migrate` is invoked on a project that already has `<!-- templateCentral: <stack>@6.0.0 -->` on line 1 (i.e., Phase 0 reports "no migration needed") **and** `.claude/harness.json` exists — or when Phase 0 routes a `@5.x` project here for its hook re-sync.

This phase checks whether seeded files have drifted from their recorded origin hashes. It never auto-repairs — it reports only.

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

```
Harness health check — templateCentral v6.0.0 / <stack>
Seeded: <seeded_at>

  AGENTS.md              UNCHANGED
  CLAUDE.md              MODIFIED   ← you customized this
  .claude/settings.json  UNCHANGED

MODIFIED files are intentional edits. To pull the latest templateCentral defaults
into them WITHOUT losing your edits, run the safe re-sync (Step 5d) — it 3-way-merges,
it does not clobber.
```

If all files are `UNCHANGED` **and** `templatecentral_version` equals the current plugin version, print:
```
✓ All harness files match their templateCentral origin and are up to date. No action needed.
```

If any file is `MISSING`, print a warning:
```
⚠ <path> is missing. This may cause templateCentral skills to behave unexpectedly.
  Re-seed it via the re-sync below (Step 5d).
```

**Step 5d: Safe re-sync (3-way merge) ⛔ GATE**

Canonical content for the re-sync comes from the harness kit — load it for the project's stack (the same files Phase 4 Step 4d loads). `<variant-file>` is `harness-kit-ts.md` for nestjs / nextjs / vite-react and `harness-kit-fastapi.md` for fastapi — load only that one variant file, never both.

These four files (`harness-kit.md`, the variant file, `harness-kit-enforcement.md`, `harness-kit-finalize.md`) are loaded by the phase table in `implementation.md` — if they are not in context, load them from there.

Offer this when there is something to apply — any `MODIFIED`/`MISSING` file, or the project's `harness.json.templatecentral_version` is older than the current plugin version (newer seeded defaults exist). **Never write without explicit user approval.** First present a dry-run plan (per file: the action + a diff preview), then on approval apply per **file class**:

- **Enforcement layer** (`.claude/hooks/*` except `.claude/hooks/local/`, `.claude/comment-hygiene-patterns.txt`, `lefthook.yml`, `.lefthook/*`, `.gitleaks.toml`, `.claude/ci-gates.sh`, the host's CI file — `.github/workflows/ci.yml` or `azure-pipelines/templatecentral-gates.yml`, `.claude/verify-harness.sh`, `.claude/regen-harness.sh`): **overwrite** with the current canonical content from this skill / `scaffold/shared/harness-kit.md`. These are not meant to be hand-edited (the verifier flags them); a re-sync resets them to canonical. CI files and hooks need human approval per write (`protect-files.sh` asks), so show their diffs in the dry-run plan. Warn if one was `MODIFIED` — and before overwriting, check whether the difference came from a `templatecentral:add` capability that extends a canonical hook (e.g. `add (redaction)` splices a companion block into `user-prompt-guard`); if so, tell the user which capability to re-apply afterwards. Any other local edit to a canonical hook (an extra protected branch, credential pattern or approval prompt) moves into a `.claude/hooks/local/` script with its own `settings.json` entry (kit Step A, "Project-local guards") in the same re-sync, so the rule survives the overwrite.
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
    `git merge-file` cleanly combines edits separated by unchanged context and leaves conflict markers only where your edit and the upstream change overlap (standard `git merge` behaviour). Resolve any markers by hand.
- **`.claude/settings.json`** (co-owned, JSON): do **not** raw-text-merge (a conflict marker breaks the JSON). Instead merge structurally — add any new seeded `hooks`/`permissions.deny` entries into the existing object without removing the user's (merge, never clobber). **Replace** (do not keep alongside) any entry pointing at a `.claude/hooks/` script whose `command` is a JSON array or whose path lacks `${CLAUDE_PROJECT_DIR}` — pre-6.0.0 forms that never ran. Remove `Edit`/`Write` denies on CI or governance paths (`.claude/settings*.json`, `.claude/hooks/**`, `.github/workflows/**`, `azure-pipelines/**`): a deny outranks the hook's ask, so it blocks the human-approved edit too. Keep every entry pointing at `.claude/hooks/local/`. Remove the `PostToolUseFailure` → `post-tool-failure.sh` entry; list `.claude/hooks/post-tool-failure.sh` and its `harness.json` entry for deletion in the dry-run plan (no longer seeded — Claude already sees tool errors).
- `MISSING` → reseed (write the current canonical content).

**After applying** (only the files actually written):
```bash
# refresh the base snapshot to the new canonical content
for p in <files written>; do mkdir -p ".claude/.harness-base/$(dirname "$p")"; cp "$p" ".claude/.harness-base/$p"; done
# recompute origin_hash for each in harness.json, and bump templatecentral_version to "$PLUGIN_VER"
bash .claude/verify-harness.sh   # confirm the enforcement layer is clean post-sync
```

If any `MISSING` file reseeded above required creating a directory that did not previously exist **outside** the paths documentation-kit.md Step 2 prunes (so `.lefthook/` or `docs/` count; anything under `.claude/`, `.github/`, or a secrets directory does not), re-run the documentation kit so that new folder gets a `README.md` too:
`documentation-kit.md` is loaded by the phase table in `implementation.md` — if it is not in context, load it from there.
Skip this re-run if nothing reseeded created a new directory.

Then re-run Step 5b/5c and confirm everything is `UNCHANGED` and up to date.

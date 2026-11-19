<!-- ref: migrate/general/harness-refresh.md
     loaded-by: migrate/SKILL.md
     prereq: The project already has .claude/harness.json (seeded by any plugin version). Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Refresh the harness of a seeded project

Brings the harness files to the current templates. Replaces only files proven unmodified, adds missing ones, never deletes, and writes the new version beside every locally edited file. A project with no `.claude/harness.json` goes through `general/implementation.md` instead.

**Proof.** A file counts as unmodified only when its hash equals its `origin_hash` in `.claude/harness.json` and it is byte-equal to its copy under `.claude/.harness-base/`. A project without both records (an older plugin version may lack them) gets every changed file as MODIFIED; the script does not guess.

1. Dry run. It writes nothing and prints one line per file:
   ```bash
   bash "<skill-dir>/general/harness-refresh.sh" <project-dir>
   ```
   Show the plan. Classes: SAME, REPLACE, MODIFIED, ADD, GONE (recorded as seeded, no longer in the templates; report only).
2. Ask the user to confirm, in one message:
   - the git tree is clean (commit first), so the refresh is one diff;
   - the REPLACE and ADD lists;
   - each MODIFIED file gets `<path>.templatecentral-new` and stays as it is;
   - whether to run the baseline compare around the refresh. It runs the project's lint, typecheck and tests and installs pinned scratch tools (network).
3. Apply. Create `<scratch>` outside the project first when the user said yes to the baseline:
   ```bash
   bash "<skill-dir>/general/harness-refresh.sh" <project-dir> --apply --baseline <scratch>
   ```
   Without the baseline, drop `--baseline <scratch>`. The script refreshes `.claude/harness.json` and the base copies for the files it wrote, then runs `harness-live.sh`. Exit 1 means a file needs the user, a check failed, or the compare found a worse number or a changed gate configuration. For the compare, follow Phase 3 A step 5 of `general/implementation.md`: show the rows, never accept a worse number by editing a threshold, a suppression or an exclusion.
4. For each `.templatecentral-new` file, merge it into the user's file with the user, then delete the `.templatecentral-new` file. For `.claude/settings.json` merge structurally, never as text. Run `bash .claude/verify-harness.sh` once merged.
5. Show `git diff`; the user commits. GONE files stay until the user chooses to remove them.

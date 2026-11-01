<!-- ref: add/documentation/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack identified; project already has the templateCentral harness seeded (scaffold or migrate). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

## Step 0 — Verify context

Need `<!-- templateCentral:` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate` (Project-migration path; its Phase 5 health check runs automatically), and if still absent, stop without writing files.

## Step 1 — Backfill per-folder documentation

```bash
cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
```

Follow it exactly over the existing project tree — it determines/updates the Azure DevOps Code Wiki and rich-content opt-ins, enumerates every folder, and writes or refreshes each folder's `README.md` (and `.order` files, if opted in).

## Step 2 — Confirm enforcement is wired

Both are seeded by `harness-kit-enforcement.md` Steps B2/B3 for any project already on this templateCentral version:

```bash
grep -q "readme-coupling:" lefthook.yml
grep -q "readme-freshness:" .github/workflows/ci.yml
```

If either check fails (an older harness), tell the user: "This project's harness predates per-folder documentation enforcement. Run `templatecentral:migrate` to pick up the harness health check and safe re-sync (Phase 5) — it will pull in the missing lefthook/CI additions without clobbering your other harness customizations." Do not hand-splice the enforcement config here — that duplicates the merge logic `migrate` Phase 5 already owns.

Both pass → done: Step 1 refreshed the docs and enforcement is wired.

<!-- ref: add/documentation/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack identified; project already has the templateCentral harness seeded (scaffold or migrate). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

## Step 0 — Verify context

Need `<!-- templateCentral:` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate` (its Phase 5 health check runs on its own), and if still absent, stop without writing files.

## Step 1 — Backfill the project docs

```bash
cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
```

Follow it exactly over the existing project tree: it settles the wiki opt-in, writes the root README and `docs/architecture.md` where missing, adds a README at each package, service or feature-module boundary, and runs the docs check.

## Step 2 — Confirm the docs check is wired

Seeded by `harness-kit-enforcement.md` Steps B2/B3 for any project on this templateCentral version:

```bash
test -f scripts/check-docs.sh
grep -q "docs-check:" lefthook.yml
```

If either check fails (an older harness), tell the user: "This project's harness predates the docs check. Run `templatecentral:migrate` to pick up the harness health check and safe re-sync (Phase 5); it pulls in the missing script and lefthook/CI additions without clobbering your other harness customizations." Do not hand-splice the enforcement config here: that duplicates the merge logic `migrate` Phase 5 already owns.

Both pass: done. Step 1 refreshed the docs and the check is wired.

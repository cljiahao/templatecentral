<!-- ref: add/documentation/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack identified; project already has the templateCentral harness seeded (scaffold or migrate). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

## Step 0 — Verify context

Look for `<!-- templateCentral:` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate` (select the Project-migration path; its
Phase 5 harness health check triggers automatically once the harness is current). Once
complete, re-check for the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

## Step 1 — Backfill per-folder documentation

```bash
cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
```

Follow it exactly over the existing project tree — it determines/updates the Azure DevOps Code Wiki opt-in, enumerates every folder, and writes or refreshes each folder's `README.md` (and `.order` files, if opted in).

## Step 2 — Confirm enforcement is wired

Both are seeded by `harness-kit.md` Step B2/B3 for any project already on this templateCentral version:

```bash
grep -q "readme-coupling:" lefthook.yml
grep -q "readme-freshness:" .github/workflows/ci.yml
```

If either check fails (an older harness), tell the user: "This project's harness predates per-folder documentation enforcement. Run `templatecentral:migrate` to pick up the harness health check and safe re-sync (Phase 5) — it will pull in the missing lefthook/CI additions without clobbering your other harness customizations." Do not hand-splice the enforcement config here — that duplicates the merge logic `migrate` Phase 5 already owns.

If both checks pass, the capability is complete: Step 1 generated/refreshed the documentation and enforcement is already wired. No further action needed.

<!-- ref: scaffold/shared/documentation-kit.md
     loaded-by: scaffold/shared/harness-kit-finalize.md Step E3 (all stacks) + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md + add/documentation/implementation.md → scaffold/SKILL.md | migrate/SKILL.md | add/SKILL.md
     prereq: A project with (or receiving) a .claude/ harness — templatecentral:scaffold has written it, templatecentral:migrate is retrofitting it, or templatecentral:add (documentation) is invoked standalone on an already-harnessed project. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold, templatecentral:migrate, and templatecentral:add skills. -->


# Shared Documentation Kit

Single source of truth for the docs a project carries and how they stay true. Stack-agnostic: the same steps run for `templatecentral:scaffold`, `templatecentral:migrate` and `templatecentral:add (documentation)`.

The model: a root `README.md` (what the project is; how to run, test and build it), root `AGENTS.md`, one `docs/architecture.md` codemap, and a short `README.md` only at a package, service or feature-module boundary. `docs/adr/` is the project's own. No README per folder, no file lists. Enforcement is one offline script, `scripts/check-docs.sh`, wired into lefthook, CI and the harness hashes by `scaffold/shared/harness-kit*.md`. Fixing a stale doc happens in the same change, without asking.

Execute all five numbered steps below, in order.

---

## Step 1. Determine the wiki opt-in (`adoWiki`)

If `.claude/harness.json` does not exist yet, skip this step and Step 4: `adoWiki` is `false`.

Read the top-level `adoWiki` field of `.claude/harness.json` (a sibling of `seeded_files`, never inside it). In a scaffold, `TC_PART=manifest` wrote it from the scaffold Step 1 answer, so nothing is asked. `true` or `false`: use it. Unset, with an interactive user: ask once, then add `"adoWiki": true` or `false` as a top-level field with the Edit tool and leave `seeded_files` alone:

> Does this project publish `docs/` to a wiki (for example an Azure DevOps Code Wiki)? If yes, I'll add a `.order` file to `docs/` so the pages render in a fixed order. (yes/no)

No interactive user (headless run): use `false` and note it in the Step 5 report.

---

## Step 2. Root README and architecture codemap

**Root `README.md`.** Existing prose is never overwritten. If none exists, create one holding the `# <project-name>` title (from `package.json` or `pyproject.toml` `name`, else the directory name), one or two lines on what the project is, and `## Run`, `## Test`, `## Build` sections with the real commands from the project's scripts. Nothing else: no file lists, no layout tour.

**Architecture codemap.** A scaffold seeds `docs/architecture.md`. For a project without one, write it from the real layout, with these sections:

- `## Layers`: each layer or module, what it owns.
- `## Dependency direction`: which layer may import which, and what never imports upward.
- `## Reuse`: where shared UI, hooks, utilities, the API client, validation, error handling and logging live, closed by the rule "search these places before creating a new helper".

Read the folders before you write. Never state a path or a dependency you have not seen. Keep it to one screen.

---

## Step 3. Boundary READMEs only

A boundary is a package, a service or a feature module: a folder other code imports through one public entry point. Only a boundary carries a `README.md`, in this shape:

```markdown
# <boundary-name>

<1-2 lines: what it is for.>

Public entry point: `<path to index file or exported module>`.

Must not depend on: <layers or modules it must never import>.
```

No `## Contents`, no file list, no per-file descriptions. An existing boundary README that is accurate stays as is.

**Folders that are not boundaries** get no README. Where an earlier run of this kit wrote per-folder READMEs (they carry `## Contents` and a `## Parent` link), list them and delete them only after the user confirms. In a headless run, leave them and report them in Step 5.

---

## Step 4. Wiki ordering (only if `adoWiki` is true)

**Gate:** run this step only when `adoWiki` is `true`. Otherwise write nothing.

The wiki is generated from `docs/` and nothing else. Write `docs/.order`: one entry per line, extension stripped, `architecture` first, then the rest alphabetically.

---

## Step 5. Check and report

Run the offline check from the project root:

```bash
bash scripts/check-docs.sh
```

Fix every finding by correcting the doc: update the link or path, or drop the claim. Never edit the script to silence a finding. Repeat until it exits 0.

Print a one-line summary:

```
docs: README <created|kept>, architecture <created|kept>, boundary READMEs: N written, M kept, K left for confirmation; check-docs exit 0
```

If `adoWiki` is true, append `docs/.order: written`. If Step 1 defaulted `adoWiki` to `false` (no interactive user), append:

```
adoWiki: defaulted to false — no interactive session available
```

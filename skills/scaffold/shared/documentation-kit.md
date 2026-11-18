<!-- ref: scaffold/shared/documentation-kit.md
     loaded-by: scaffold/shared/harness-kit-finalize.md Step E3 (all stacks) + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md + add/documentation/implementation.md → scaffold/SKILL.md | migrate/SKILL.md | add/SKILL.md
     prereq: A project with (or receiving) a .claude/ harness — templatecentral:scaffold has written it, templatecentral:migrate is retrofitting it, or templatecentral:add (documentation) is invoked standalone on an already-harnessed project. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold, templatecentral:migrate, and templatecentral:add skills. -->


# Shared Documentation Kit

Single source of truth for the docs a project carries and how they stay true. Stack-agnostic: the same steps run for `templatecentral:scaffold`, `templatecentral:migrate` and `templatecentral:add (documentation)`.

The model: a root `README.md` (what the project is; how to run, test and build it), root `AGENTS.md`, one `docs/architecture.md` codemap, and a short `README.md` only at a package, service or feature-module boundary. `docs/adr/` is the project's own. No README per folder, no file lists. Enforcement is one offline script, `scripts/check-docs.sh`, wired into lefthook, CI and the harness hashes by `scaffold/shared/harness-kit*.md`. Fixing a stale doc happens in the same change, without asking.

Execute all five numbered steps below, in order.

---

## Step 1. Determine the wiki opt-in (`adoWiki`)

In a scaffold, the user answered in scaffold Step 1 and `harness-kit-finalize.md` Step E wrote the answer into `.claude/harness.json`, so the read function returns it and nothing is asked. The ask and write logic serves `templatecentral:migrate` and `templatecentral:add (documentation)`, and any project whose manifest lacks the field.

**Guard first:** if `.claude/harness.json` does not exist yet, skip this step and Step 4: `adoWiki` is `false`.

Read the top-level `adoWiki` field from `.claude/harness.json`, a **sibling** of `seeded_files`, never inside it:

```json
{
  "stack": "<stack>",
  "seeded_at": "<ISO-date>",
  "adoWiki": false,
  "seeded_files": { "...": "..." }
}
```

**Read function** (portable: jq → node → python3 fallback). Prints `true`, `false`, or an empty string if the field is unset:

```bash
read_adowiki() {
  local manifest=".claude/harness.json"
  [ -f "$manifest" ] || { echo ""; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r 'if has("adoWiki") then (.adoWiki | tostring) else "" end' "$manifest"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs"),j=JSON.parse(fs.readFileSync("'"$manifest"'","utf8"));process.stdout.write(Object.prototype.hasOwnProperty.call(j,"adoWiki")?String(j.adoWiki):"")'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json
j=json.load(open("'"$manifest"'"))
print(str(j["adoWiki"]).lower() if "adoWiki" in j else "")'
  else
    echo "read_adowiki: need jq, node, or python3" >&2
    return 3
  fi
}
```

**Write function** (same fallback order). Sets or replaces the top-level `adoWiki` field only — it must never read, write, or otherwise touch `seeded_files`:

```bash
write_adowiki() {
  local value="$1"   # literal "true" or "false"
  local manifest=".claude/harness.json"
  [ -f "$manifest" ] || { echo "write_adowiki: $manifest missing" >&2; return 1; }
  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/harness-json.XXXXXX")
    jq --argjson v "$value" '.adoWiki = $v' "$manifest" > "$tmp" && mv "$tmp" "$manifest"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs"),p="'"$manifest"'",j=JSON.parse(fs.readFileSync(p,"utf8"));j.adoWiki='"$value"';fs.writeFileSync(p,JSON.stringify(j,null,2)+"\n");'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json
p="'"$manifest"'"
j=json.load(open(p))
j["adoWiki"]='"$([ "$value" = "true" ] && echo True || echo False)"'
open(p,"w").write(json.dumps(j,indent=2)+"\n")'
  else
    echo "write_adowiki: need jq, node, or python3" >&2
    return 3
  fi
}
```

**Decision logic:**

1. `existing=$(read_adowiki)`
2. If `$existing` is `true` or `false`, use it. Do not ask again.
3. If `$existing` is empty **and an interactive user is available**, ask exactly once, worded around:

   > Does this project publish `docs/` to a wiki (for example an Azure DevOps Code Wiki)? If yes, I'll add a `.order` file to `docs/` so the pages render in a fixed order. (yes/no)

   **No interactive user** (headless run): default to `false` and note it in the Step 5 report.

4. Persist the answer immediately with `write_adowiki "true"` or `write_adowiki "false"`.

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

**Gate:** run this step only when `read_adowiki` returns `true`. Otherwise write nothing.

The wiki is generated from `docs/` and nothing else. Write `docs/.order`, one entry per line with the extension stripped: `architecture` first, then every other page and subfolder of `docs/` in alphabetical order. Regenerate it whenever a page is added or removed.

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

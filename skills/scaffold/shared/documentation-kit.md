<!-- ref: scaffold/shared/documentation-kit.md
     loaded-by: scaffold/shared/harness-kit.md (all stacks) + migrate/general/implementation.md + add/documentation/implementation.md → scaffold/SKILL.md | migrate/SKILL.md | add/SKILL.md
     prereq: A project with (or receiving) a .claude/ harness — templatecentral:scaffold has written it, templatecentral:migrate is retrofitting it, or templatecentral:add (documentation) is invoked standalone on an already-harnessed project. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold, templatecentral:migrate, and templatecentral:add skills. -->

# Shared Documentation Kit

This file is the single source of truth for the per-folder `README.md` structure and its generation algorithm, plus the optional per-folder `.order` file that makes an Azure DevOps Code Wiki render correctly. It is stack-agnostic — the same five steps run unmodified whether the caller is `templatecentral:scaffold`, `templatecentral:migrate`, or `templatecentral:add (documentation)`.

**Scope:** content generation only. Enforcement (the `readme-coupling` lefthook check and the `readme-freshness` CI job) lives in `scaffold/shared/harness-kit.md`, not here.

Execute all five numbered steps below, in order.

---

## Step 1. Determine the Azure DevOps Code Wiki opt-in

**Guard first:** if `.claude/harness.json` does not exist yet, skip Step 1 and Step 4 entirely — proceed directly to Step 2 and Step 3. This should not normally happen, since this kit is loaded after `harness.json` is created, but the guard keeps the kit safe to invoke standalone (e.g. a future `templatecentral:add (documentation)` run against a project whose harness hasn't landed yet).

Read the top-level `adoWiki` field from `.claude/harness.json`. This field lives at the top level of the manifest, as a **sibling** of `seeded_files` — never inside it:

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
    tmp=$(mktemp)
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
2. If `$existing` is `true` or `false`, use it. Do not ask the user again — the field already records their answer.
3. If `$existing` is empty (field unset — first time this kit runs on this project), ask the user **exactly once**, worded around:

   > Does this project publish its repo to an Azure DevOps Code Wiki? If yes, I'll also maintain a `.order` file per folder so the wiki tree renders correctly — a parent folder with only subfolders and no file of its own shows up blank otherwise. (yes/no)

4. Persist the answer immediately with `write_adowiki "true"` or `write_adowiki "false"` so future runs (this session or a later one) read it back in step 2 instead of asking again.

---

## Step 2. Enumerate folders

Enumerate every project directory with a single portable `find` command, pruning dependency/build output and VCS/harness-internal directories so generated or vendored trees are never touched:

```bash
find . \( \
    -path './.git' -o \
    -name node_modules -o \
    -name .next -o \
    -name dist -o \
    -name coverage -o \
    -name .turbo -o \
    -name .venv -o \
    -name __pycache__ -o \
    -name .pytest_cache -o \
    -name .ruff_cache -o \
    -name .mypy_cache -o \
    -name htmlcov -o \
    -path './.claude/.harness-base' \
  \) -prune -o -type d -print
```

This is the working set for Step 3 (one `README.md` decision per directory it prints, including `.` — the repo root) and, when `adoWiki` is true, for Step 4.

---

## Step 3. Write or refresh README.md per folder

**Read before you write.** For every folder in the Step 2 working set, actually list its immediate children (`ls`) and look at what they are before writing `Purpose` or `Connectivity`. Never invent behavior, a component's role, or a subfolder's relationship to its siblings — if it isn't visible from the folder's actual contents (file names, a couple of representative file bodies if genuinely ambiguous), don't assert it.

### Repo root — special case

The root folder's `README.md` is a human-facing project readme (title, badges, quickstart, etc. — whatever already exists there). **That prose must never be overwritten.** Only a missing `## Structure` section may be added to it:

1. Check whether the existing root `README.md` already has a `## Structure` heading. If it does, leave the file untouched.
2. If it does not, append a `## Structure` section at the end, generated the same way as `Contents` + `Connectivity` below (the root always has subfolders, so `Connectivity` is always included there). Do not touch any text above the appended section.

### Every other folder — full template

For every non-root folder, create or fully regenerate its `README.md` from this template:

```markdown
# <folder-name>

## Purpose
<1-2 lines: what this folder is for, grounded in what you actually saw in its contents>

## Contents
- `<child-1>`
- `<child-2>`
- `<child-n>`

## Connectivity
<2-4 sentences — this section is included ONLY if the folder contains at least one subfolder>

## Parent
[<parent-folder-name>](../README.md)
```

`## Parent` is omitted at the repo root (there is no parent to link to) — this branch only applies to non-root folders, which always have one.

**Section rules:**

- **Purpose** — 1-2 lines. What the folder holds and why it exists as its own unit.
- **Contents** — mechanical, not narrative: one bullet per immediate child (file or subfolder), derived directly from `ls`. Do not add descriptive prose per bullet beyond the child's own name; this section is a manifest, not a summary.
- **Connectivity** — deliberately capped at 2-4 sentences, and included only for folders that contain subfolders. Say how the subfolders relate to each other and to the parent (data flow, layering, dependency direction) — not what each one does individually (that's each subfolder's own `Purpose`). Keep this short on purpose: verbose, narratively-generated per-folder AI context measurably hurts agent task performance (per an ETH Zurich study cited in this feature's design doc) — the goal is a structural map an agent can skim in seconds, not an essay.
- **Parent** — a relative link to the immediate parent's `README.md` (always `../README.md`, since Parent is always one level up).

If a `README.md` already exists for a non-root folder and its structural sections are already accurate against the folder's current contents, leave it unchanged rather than rewriting an identical file.

---

## Step 4. `.order` files (only if adoWiki is true)

**Gate:** run this step only when `read_adowiki` returns `true`. If it returns `false` (or the Step 1 guard skipped Step 1 entirely because `.claude/harness.json` didn't exist), skip Step 4 in its entirety — do not write, update, or delete any `.order` file.

When `adoWiki` is true, write a `.order` file into every folder from the Step 2 working set (including the repo root). Azure DevOps Code Wiki uses `.order` to decide sibling ordering and — critically — to render a parent page for folders that contain only subfolders and no file of their own (without it, such a folder renders blank in the wiki tree).

**`.order` contents, one entry per line, extension stripped:**

1. `README` first (always — it is the folder's own wiki page).
2. Every other immediate child (file or subfolder) next, in alphabetical order, with its extension stripped (`architecture.md` → `architecture`, `utils/` → `utils`).

Example, for a folder containing `README.md`, `architecture.md`, and subfolders `components/` and `utils/`:

```
README
architecture
components
utils
```

Regenerate `.order` alongside its folder's `README.md` in Step 3 (same pass) so the two never drift out of sync with the folder's actual current contents.

---

## Step 5. Report

Print a one-line summary of what happened:

```
README.md: N created, M updated, K unchanged
```

If `adoWiki` is true, append a second line:

```
.order: J written
```

Omit the `.order` line entirely when `adoWiki` is false or Step 4 was skipped.

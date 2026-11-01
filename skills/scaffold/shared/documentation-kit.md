<!-- ref: scaffold/shared/documentation-kit.md
     loaded-by: scaffold/shared/harness-kit-finalize.md Step E3 (all stacks) + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md + add/documentation/implementation.md → scaffold/SKILL.md | migrate/SKILL.md | add/SKILL.md
     prereq: A project with (or receiving) a .claude/ harness — templatecentral:scaffold has written it, templatecentral:migrate is retrofitting it, or templatecentral:add (documentation) is invoked standalone on an already-harnessed project. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold, templatecentral:migrate, and templatecentral:add skills. -->

# Shared Documentation Kit

Single source of truth for the per-folder `README.md` structure and generation, plus the optional per-folder `.order` file for an Azure DevOps Code Wiki. Stack-agnostic: the same five steps run for `templatecentral:scaffold`, `templatecentral:migrate` and `templatecentral:add (documentation)`.

**Scope:** content only. Enforcement (`readme-coupling` lefthook check, `readme-freshness` CI job) lives in `scaffold/shared/harness-kit*.md` Steps B2/B3.

Execute all five numbered steps below, in order.

---

## Step 1. Determine per-project opt-ins

**Guard first:** if `.claude/harness.json` does not exist yet, skip Step 1 (1a and 1b) and Step 4 — go to Steps 2 and 3 with `adoWiki` and `richReadme` both `false`.

### Step 1a. Azure DevOps Code Wiki opt-in (`adoWiki`)

Read the top-level `adoWiki` field from `.claude/harness.json` — a **sibling** of `seeded_files`, never inside it:

```json
{
  "stack": "<stack>",
  "seeded_at": "<ISO-date>",
  "adoWiki": false,
  "richReadme": false,
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
2. If `$existing` is `true` or `false`, use it. Do not ask again.
3. If `$existing` is empty **and an interactive user is available**, ask exactly once, worded around:

   > Does this project publish its repo to an Azure DevOps Code Wiki? If yes, I'll also maintain a `.order` file per folder (so the wiki tree renders correctly) and a `<folder-name>.md` sibling file next to each folder (so that folder's own wiki page shows real content instead of a blank cover page) — this works whether you consume it via native "Publish code as wiki" or a manual/provisioned-wiki import. (yes/no)

   **No interactive user** (headless run): default to `false` and note it in the Step 5 report.

4. Persist the answer immediately with `write_adowiki "true"` or `write_adowiki "false"`.

### Step 1b. Rich per-file content opt-in (`richReadme`)

Read the top-level `richReadme` field from `.claude/harness.json` — a **sibling** of `seeded_files`, never inside it.

**Read function** (portable: jq → node → python3 fallback). Prints `true`, `false`, or an empty string if the field is unset:

```bash
read_rich_readme() {
  local manifest=".claude/harness.json"
  [ -f "$manifest" ] || { echo ""; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r 'if has("richReadme") then (.richReadme | tostring) else "" end' "$manifest"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs"),j=JSON.parse(fs.readFileSync("'"$manifest"'","utf8"));process.stdout.write(Object.prototype.hasOwnProperty.call(j,"richReadme")?String(j.richReadme):"")'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json
j=json.load(open("'"$manifest"'"))
print(str(j["richReadme"]).lower() if "richReadme" in j else "")'
  else
    echo "read_rich_readme: need jq, node, or python3" >&2
    return 3
  fi
}
```

**Write function** (same fallback order). Sets or replaces the top-level `richReadme` field only — it must never read, write, or otherwise touch `seeded_files`:

```bash
write_rich_readme() {
  local value="$1"   # literal "true" or "false"
  local manifest=".claude/harness.json"
  [ -f "$manifest" ] || { echo "write_rich_readme: $manifest missing" >&2; return 1; }
  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp=$(mktemp)
    jq --argjson v "$value" '.richReadme = $v' "$manifest" > "$tmp" && mv "$tmp" "$manifest"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs"),p="'"$manifest"'",j=JSON.parse(fs.readFileSync(p,"utf8"));j.richReadme='"$value"';fs.writeFileSync(p,JSON.stringify(j,null,2)+"\n");'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json
p="'"$manifest"'"
j=json.load(open(p))
j["richReadme"]='"$([ "$value" = "true" ] && echo True || echo False)"'
open(p,"w").write(json.dumps(j,indent=2)+"\n")'
  else
    echo "write_rich_readme: need jq, node, or python3" >&2
    return 3
  fi
}
```

**Decision logic:**

1. `existing=$(read_rich_readme)`
2. If `$existing` is `true` or `false`, use it. Do not ask again.
3. If `$existing` is empty **and an interactive user is available**, ask exactly once, worded around:

   > Do you want per-folder READMEs to carry rich content — a `Contents` bullet per file with a real one-line description of what it does (its actual exported functions/components/constants, schemas, route handlers, or other genuinely defining behavior — read from the file, not guessed), and a `Connectivity` section with no length cap? This is more useful to read but only stays accurate as long as you keep `readme-coupling`/`readme-freshness` enforcement active — a rich description silently goes stale the moment the file changes without its README following. If no, I'll keep Contents to a plain filename manifest and Connectivity capped at 2-4 sentences. (yes/no)

   **No interactive user** (headless run): default to `false` and note it in the Step 5 report.

4. Persist the answer immediately with `write_rich_readme "true"` or `write_rich_readme "false"`.

---

## Step 2. Enumerate folders

Enumerate project directories with one portable `find`, pruning dependency/build output, VCS/harness-internal directories, and every path the harness protects:

```bash
find . \( \
    -path './.git' -o \
    -name node_modules -o \
    -name .next -o \
    -name dist -o \
    -name build -o \
    -name coverage -o \
    -name .turbo -o \
    -name .venv -o \
    -name __pycache__ -o \
    -name .pytest_cache -o \
    -name .ruff_cache -o \
    -name .mypy_cache -o \
    -name .pyright -o \
    -name htmlcov -o \
    -name .stryker-tmp -o \
    -name .mutmut-cache -o \
    -name .github -o \
    -name .azuredevops -o \
    -name azure-pipelines -o \
    -name secrets -o \
    -name .secrets -o \
    -name .claude -o \
    -name .lefthook -o \
    -path './.claude/.harness-base' \
  \) -prune -o -type d -print
```

**CI, secrets, `.claude` and `.lefthook` folders are pruned** because `protect-files.sh` blocks or asks on writes there; the `readme-freshness` gate never demands a README in them.

**Respect the project's own `.gitignore` too.** After the `find`, drop any entry the project ignores. Without a git repository yet, the check below keeps everything:

```bash
tmp=$(mktemp)
find . \( \
    -path './.git' -o -name node_modules -o -name .next -o -name dist -o -name build -o \
    -name coverage -o -name .turbo -o -name .venv -o -name __pycache__ -o \
    -name .pytest_cache -o -name .ruff_cache -o -name .mypy_cache -o -name .pyright -o \
    -name htmlcov -o -name .stryker-tmp -o -name .mutmut-cache -o \
    -name .github -o -name .azuredevops -o -name azure-pipelines -o \
    -name secrets -o -name .secrets -o -name .claude -o \
    -path './.claude/.harness-base' \
  \) -prune -o -type d -print > "$tmp"

working_set=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r folder; do
    git check-ignore -q "$folder" || working_set="$working_set$folder
"
  done < "$tmp"
else
  working_set=$(cat "$tmp")
fi
rm -f "$tmp"
```

`$working_set` (one folder per line, including `.` — the repo root) is the working set for Step 3 and, when `adoWiki` is true, Step 4.

---

## Step 3. Write or refresh README.md per folder

**Read before you write.** For every folder in the working set, `ls` its immediate children before writing `Purpose` or `Connectivity`. Never invent behavior, a component's role, or a subfolder's relationship — if it isn't visible from the contents (file names, a few file bodies if ambiguous), don't assert it. **When `richReadme` is true**, read every child file before writing its `Contents` bullet — never infer from the name. One read pass: reuse a file already opened for `Purpose`/`Connectivity`.

### Repo root — special case

The root `README.md` is the human-facing project readme. **That prose must never be overwritten.** Only a missing `## Structure` section may be added:

1. **If no root `README.md` exists:** create one holding only a `# <project-name>` title (from `package.json`/`pyproject.toml` `name`, else the directory name), then continue.
2. Check whether the (now-existing) root `README.md` already has a `## Structure` heading. If it does, leave the file untouched.
3. If not, append `## Structure` at the end with `### Contents` and `### Connectivity` subheadings, generated like the sections below. Do not touch any text above it.

### Every other folder — full template

For every non-root folder, create or fully regenerate its `README.md` from this template:

```markdown
# <folder-name>

## Purpose
<1-2 lines: what this folder is for, grounded in what you actually saw in its contents>

## Contents
- `<child-1>`
- `<child-2>/`
- `<child-n>`

## Connectivity
<2-4 sentences (richReadme=false) or as deep as genuinely useful (richReadme=true) — this section is included ONLY if the folder contains at least one subfolder>

## Parent
[<parent-folder-name>](../README.md)
```

`## Parent` never appears at the repo root.

**Section rules:**

- **Purpose** — 1-2 lines. What the folder holds and why it exists as its own unit.
- **Contents** — one bullet per immediate child, sorted alphabetically so an unchanged folder regenerates byte-identical. **Exclude any child that matches the Step 2 prune list** or is gitignored. Subfolders get a trailing `/` (e.g. `components/`); files don't.
  - **`richReadme` false (default):** a manifest — no prose beyond the child's own name.
  - **`richReadme` true:** each bullet becomes `` `<child>` — <real one-line description> `` — the file's real exports, schemas, route handlers or other defining behavior, read from the file, never a restatement of the filename. Subfolders keep just their name. **Exception:** lockfiles (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `poetry.lock`, `Cargo.lock`, etc.) and binary files get a brief generic description (e.g. "locked dependency versions") without opening them.
- **Connectivity** — only for folders with subfolders. How the subfolders relate to each other and the parent (data flow, layering, dependency direction), not what each does.
  - **`richReadme` false (default):** capped at 2-4 sentences, to limit staleness.
  - **`richReadme` true:** no cap; still relational only.
- **Parent** — `../README.md`.

If an existing non-root `README.md` is already accurate, leave it unchanged. **When `richReadme` is true**, judge accuracy by whether the descriptions still hold, not by exact-string comparison; rewrite only what is stale.

---

## Step 4. `.order` files and wiki-page promotion files (only if adoWiki is true)

**Gate:** run this step only when `read_adowiki` returns `true`. Otherwise do not write, update, or delete any `.order` file or promotion file.

Two artifacts, because Azure DevOps consumes a repo two ways:

- **Native "Publish code as wiki"** builds a page per folder; `.order` fixes sibling order and keeps an empty parent folder from rendering blank.
- **A manual or provisioned-wiki import** does not nest from folder structure: a folder's page needs a Markdown file **named like the folder**, as its **sibling** in the parent directory.

### 4a. `.order` files

Write a `.order` file into every working-set folder (including the repo root). **One entry per line, extension stripped:**

1. `README` first (always — it is the folder's own wiki page).
2. Every other immediate child (file or subfolder) next, in alphabetical order, with its extension stripped (`architecture.md` → `architecture`, `utils/` → `utils`).

Example, for a folder containing `README.md`, `architecture.md`, and subfolders `components/` and `utils/`:

```
README
architecture
components
utils
```

### 4b. Folder-promotion files

For every **non-root** working-set folder, write `<folder-name>.md` in the *parent* directory, next to the folder: a **byte-identical copy** of that folder's `README.md`.

**Collision safety:** if `<folder-name>.md` exists and is neither a copy of the current `README.md` nor of a prior run's, it is human-authored — do not overwrite it; flag it in the Step 5 report.

The repo root gets no promotion file.

Regenerate `.order` (4a) and the promotion copy (4b) in the same pass as the folder's `README.md`.

---

## Step 5. Report

Print a one-line summary of what happened:

```
README.md: N created, M updated, K unchanged
```

If `richReadme` is true, append `(rich mode)` to that line:

```
README.md: N created, M updated, K unchanged (rich mode)
```

If `adoWiki` is true, append lines for both Step 4 artifacts, plus a usage note and any promotion-file conflicts found:

```
.order: J written
wiki-page promotion files: P written (Q skipped — pre-existing foreign content: <path>, <path>)
Import with Repos → Wikis → Publish code as wiki pointed at this branch/root, or via a manual/provisioned-wiki import — folder pages now carry real content either way.
```

Omit the `(Q skipped — ...)` clause when no conflicts were found. Omit all `.order`/promotion-file/usage-note lines entirely when `adoWiki` is false or Step 4 was skipped.

If Step 1a defaulted `adoWiki` to `false` (no interactive user), append:

```
adoWiki: defaulted to false — no interactive session available
```

If Step 1b defaulted `richReadme` to `false` (no interactive user), append:

```
richReadme: defaulted to false — no interactive session available
```

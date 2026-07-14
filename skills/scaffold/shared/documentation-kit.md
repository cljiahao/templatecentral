<!-- ref: scaffold/shared/documentation-kit.md
     loaded-by: scaffold/shared/harness-kit.md (all stacks) + migrate/general/implementation.md + add/documentation/implementation.md → scaffold/SKILL.md | migrate/SKILL.md | add/SKILL.md
     prereq: A project with (or receiving) a .claude/ harness — templatecentral:scaffold has written it, templatecentral:migrate is retrofitting it, or templatecentral:add (documentation) is invoked standalone on an already-harnessed project. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold, templatecentral:migrate, and templatecentral:add skills. -->

# Shared Documentation Kit

This file is the single source of truth for the per-folder `README.md` structure and its generation algorithm, plus the optional per-folder `.order` file that makes an Azure DevOps Code Wiki render correctly. It is stack-agnostic — the same five steps run unmodified whether the caller is `templatecentral:scaffold`, `templatecentral:migrate`, or `templatecentral:add (documentation)`.

**Scope:** content generation only. Enforcement (the `readme-coupling` lefthook check and the `readme-freshness` CI job) lives in `scaffold/shared/harness-kit.md`, not here.

Execute all five numbered steps below, in order.

---

## Step 1. Determine per-project opt-ins

**Guard first:** if `.claude/harness.json` does not exist yet, skip Step 1 (1a and 1b) and Step 4 entirely — proceed directly to Step 2 and Step 3, treating both `adoWiki` and `richReadme` as `false` for this run. This should not normally happen, since this kit is loaded after `harness.json` is created, but the guard keeps the kit safe to invoke standalone (e.g. a future `templatecentral:add (documentation)` run against a project whose harness hasn't landed yet).

### Step 1a. Azure DevOps Code Wiki opt-in (`adoWiki`)

Read the top-level `adoWiki` field from `.claude/harness.json`. This field lives at the top level of the manifest, as a **sibling** of `seeded_files` — never inside it:

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
2. If `$existing` is `true` or `false`, use it. Do not ask the user again — the field already records their answer.
3. If `$existing` is empty (field unset — first time this kit runs on this project) **and an interactive user is available to ask**, ask exactly once, worded around:

   > Does this project publish its repo to an Azure DevOps Code Wiki? If yes, I'll also maintain a `.order` file per folder so the wiki tree renders correctly — a parent folder with only subfolders and no file of its own shows up blank otherwise. (yes/no)

   **No interactive user available** (a headless/automated invocation — e.g. a CI-driven scaffold, or an agent run with no human to answer): default to `false` and note the assumption in the Step 5 report (e.g. `adoWiki: defaulted to false — no interactive session available`), rather than hanging or guessing silently.

4. Persist the answer immediately with `write_adowiki "true"` or `write_adowiki "false"` so future runs (this session or a later one) read it back in step 2 instead of asking again.

### Step 1b. Rich per-file content opt-in (`richReadme`)

Read the top-level `richReadme` field from `.claude/harness.json`, the same way as `adoWiki` — a **sibling** of `seeded_files`, never inside it (see the schema in Step 1a).

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
2. If `$existing` is `true` or `false`, use it. Do not ask the user again — the field already records their answer.
3. If `$existing` is empty (field unset — first time this kit runs on this project) **and an interactive user is available to ask**, ask exactly once, worded around:

   > Do you want per-folder READMEs to carry rich content — a `Contents` bullet per file with a real one-line description of what it does (its actual exported functions/components/constants, schemas, route handlers, or other genuinely defining behavior — read from the file, not guessed), and a `Connectivity` section with no length cap? This is more useful to read but only stays accurate as long as you keep `readme-coupling`/`readme-freshness` enforcement active — a rich description silently goes stale the moment the file changes without its README following. If no, I'll keep Contents to a plain filename manifest and Connectivity capped at 2-4 sentences. (yes/no)

   **No interactive user available** (a headless/automated invocation — e.g. a CI-driven scaffold, or an agent run with no human to answer): default to `false` and note the assumption in the Step 5 report (e.g. `richReadme: defaulted to false — no interactive session available`), rather than hanging or guessing silently.

4. Persist the answer immediately with `write_rich_readme "true"` or `write_rich_readme "false"` so future runs (this session or a later one) read it back in step 2 instead of asking again.

---

## Step 2. Enumerate folders

Enumerate every project directory with a single portable `find` command, pruning dependency/build output and VCS/harness-internal directories so generated or vendored trees are never touched:

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
    -path './.claude/.harness-base' \
  \) -prune -o -type d -print
```

**Respect the project's own `.gitignore` too.** The prune list above only covers well-known dependency/build directories common across templateCentral's own scaffolds — it cannot anticipate every project-specific ignore pattern (e.g. a custom `log/` directory). After the `find` above, drop any remaining entry that the project itself ignores, so this kit never writes a `README.md` that's invisible to git, CI, and teammates. If no git repository exists yet (very early in a fresh scaffold, before `git init` has run), skip this filter entirely and rely on the hardcoded prune list alone — the check below degrades to a no-op filter (keeps everything) in that case, which is safe:

```bash
tmp=$(mktemp)
find . \( \
    -path './.git' -o -name node_modules -o -name .next -o -name dist -o -name build -o \
    -name coverage -o -name .turbo -o -name .venv -o -name __pycache__ -o \
    -name .pytest_cache -o -name .ruff_cache -o -name .mypy_cache -o -name .pyright -o \
    -name htmlcov -o -name .stryker-tmp -o -name .mutmut-cache -o \
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

`$working_set` (one folder path per line) is the final list — use it for Step 3 and, when `adoWiki` is true, Step 4.

This is the working set for Step 3 (one `README.md` decision per directory it prints, including `.` — the repo root) and, when `adoWiki` is true, for Step 4.

---

## Step 3. Write or refresh README.md per folder

**Read before you write.** For every folder in the Step 2 working set, actually list its immediate children (`ls`) and look at what they are before writing `Purpose` or `Connectivity`. Never invent behavior, a component's role, or a subfolder's relationship to its siblings — if it isn't visible from the folder's actual contents (file names, a couple of representative file bodies if genuinely ambiguous), don't assert it. **When `richReadme` is true** (determined in Step 1b), this applies to every child file too: open and actually read each one before writing its `Contents` bullet — never infer what a file does from its name alone. This is one read pass, not two — if a file was already opened above to resolve a `Purpose`/`Connectivity` ambiguity, reuse that same read for its `Contents` bullet instead of opening it again.

### Repo root — special case

The root folder's `README.md` is a human-facing project readme (title, badges, quickstart, etc. — whatever already exists there). **That prose must never be overwritten.** Only a missing `## Structure` section may be added to it:

1. **If no root `README.md` exists at all** (nothing upstream of this kit created one — this can happen on `templatecentral:add (documentation)`/`templatecentral:migrate` light-adoption against a project with no README, or a scaffold whose stack template doesn't seed one): create a minimal one first — a `# <project-name>` title line (derived from the directory name or `package.json`/`pyproject.toml`'s `name` field if present), nothing else — then proceed to step 2 below as if it always existed.
2. Check whether the (now-existing) root `README.md` already has a `## Structure` heading. If it does, leave the file untouched.
3. If it does not, append a `## Structure` section at the end, generated the same way as `Contents` + `Connectivity` below — but nested one level down, as `### Contents` and `### Connectivity` subheadings under `## Structure` (the root always has subfolders, so `### Connectivity` is always included there). Do not touch any text above the appended section.

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

`## Parent` is omitted at the repo root (there is no parent to link to) — this branch only applies to non-root folders, which always have one.

**Section rules:**

- **Purpose** — 1-2 lines. What the folder holds and why it exists as its own unit.
- **Contents** — one bullet per immediate child (file or subfolder), derived directly from `ls`, sorted alphabetically (not raw `ls` order) so an unchanged folder produces byte-identical output run to run — this is what makes the "leave unchanged if accurate" freshness check below deterministic. **Exclude any child that matches the Step 2 prune list** (`node_modules`, `dist`, `.git`, etc.) or is itself gitignored, the same way Step 2 excludes them from the folder working set — otherwise the root's own `Contents` would list `node_modules/`, `.git`, build artifacts, and similar noise as if they were real project structure. Subfolders get a trailing `/` (e.g. `components/`); files don't — so a reader can tell them apart at a glance.
  - **`richReadme` false (default):** mechanical, not narrative — a manifest, not a summary. Do not add descriptive prose per bullet beyond the child's own name.
  - **`richReadme` true:** each bullet becomes `` `<child>` — <real one-line description> `` — the child's actual exported functions/components/constants, schemas, route handlers, or other genuinely defining behavior, taken from actually reading the file (per the Step 3 intro's read-before-you-write rule), never a restatement of the filename. Subfolders still just get their name (a subfolder's own `Purpose` covers it) — this only enriches file bullets. **Exception:** known lockfiles (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `poetry.lock`, `Cargo.lock`, etc.) and binary files (images, fonts, and other non-text formats) get a brief generic description (e.g. "locked dependency versions") without opening them — reading a multi-thousand-line lockfile or a binary asset cover-to-cover for one bullet isn't worth the cost.
- **Connectivity** — included only for folders that contain subfolders. Say how the subfolders relate to each other and to the parent (data flow, layering, dependency direction) — not what each one does individually (that's each subfolder's own `Purpose`).
  - **`richReadme` false (default):** capped at 2-4 sentences. This cap is a safe-by-default choice, not a mitigation for the agent-performance regression an ETH Zurich study measured for verbose per-folder AI context — that study evaluates AGENTS.md-style files, which are forced into every agent task's context regardless of relevance; a per-folder `README.md` is opened on demand, only when an agent chooses to navigate there — much closer to how a human uses documentation — so that finding doesn't directly transfer here. The real risk this cap manages is staleness: a detailed claim about what subfolders do or how they relate goes silently wrong the moment the code changes without the README following — exactly what the `readme-coupling` lefthook check and `readme-freshness` CI job (`scaffold/shared/harness-kit.md`) exist to catch. Capping the default keeps that risk low for projects that may not keep that enforcement airtight.
  - **`richReadme` true:** no sentence cap — write real cross-file relationships, as deep as genuinely useful. Still relational information only (how subfolders connect), not restating each child's own `Purpose`. This is the escape hatch for projects that do keep `readme-coupling`/`readme-freshness` enforcement active and want documentation-kit's on-demand per-folder READMEs to carry more than a structural skim.
- **Parent** — a relative link to the immediate parent's `README.md` (always `../README.md`, since Parent is always one level up).

If a `README.md` already exists for a non-root folder and its structural sections are already accurate against the folder's current contents, leave it unchanged rather than rewriting an identical file. **When `richReadme` is true**, don't expect byte-identical regeneration the way the mechanical `Contents` listing guarantees — judge "accurate" by whether the existing descriptions still hold for the file's current contents, not by exact-string comparison; only rewrite what's actually stale.

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

If `richReadme` is true, append `(rich mode)` to that same line instead of printing it plain:

```
README.md: N created, M updated, K unchanged (rich mode)
```

If `adoWiki` is true, append a line:

```
.order: J written
```

Omit the `.order` line entirely when `adoWiki` is false or Step 4 was skipped.

If Step 1a defaulted `adoWiki` to `false` because no interactive user was available, append a line noting the assumption:

```
adoWiki: defaulted to false — no interactive session available
```

If Step 1b defaulted `richReadme` to `false` because no interactive user was available, append a line noting the assumption:

```
richReadme: defaulted to false — no interactive session available
```

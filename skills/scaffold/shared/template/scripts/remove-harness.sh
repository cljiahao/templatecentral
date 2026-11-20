#!/usr/bin/env bash
# Removes the seeded harness listed in .claude/harness.json. Offline, read-only unless --apply is given.
# Usage: remove-harness.sh [--apply] [--force <path>]...
# Dry run by default: lists what would go and what is kept. A file whose content differs from the seeded hash is kept
# unless named with --force. Source code, lockfiles, .env files and project docs are never removed, even with --force.
# Restores nothing and edits no file content: undo the AGENTS.md tail, .gitignore lines and git hooks by hand.
set -uo pipefail

apply=0
force=""

die() {
  printf 'remove-harness: %s\n' "$1" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --force)
      [ $# -ge 2 ] || die "--force needs a path from the dry-run output"
      force="$force
$2"
      shift
      ;;
    *) die "usage: remove-harness.sh [--apply] [--force <path>]..." ;;
  esac
  shift
done

root=$(cd "$(dirname "$0")/.." && pwd) || die "cannot find the project root"
cd "$root" || die "cannot enter $root"
manifest=.claude/harness.json
[ -f "$manifest" ] || die "$manifest is missing: nothing seeded here, or the harness is already removed."

# Prints the SHA-256 of a file.
sha() {
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

# Prints "path<TAB>origin_hash" for every seeded file.
read_manifest() {
  if command -v jq > /dev/null 2>&1; then
    jq -er '.seeded_files | to_entries[] | "\(.value.path)\t\(.value.origin_hash)"' "$manifest"
  elif command -v node > /dev/null 2>&1; then
    node -e 'const m=JSON.parse(require("fs").readFileSync(".claude/harness.json","utf8"));for(const v of Object.values(m.seeded_files))console.log(v.path+"\t"+v.origin_hash)'
  elif command -v python3 > /dev/null 2>&1; then
    python3 -c 'import json;m=json.load(open(".claude/harness.json"));[print(str(v["path"])+"\t"+str(v["origin_hash"])) for v in m["seeded_files"].values()]'
  else
    return 3
  fi
}

# True for paths that are the project's own, never harness.
is_protected() {
  case "$1" in
    .env | .env.* | */.env | */.env.* | *.lock | *.lockb | *lock.json | *lock.yaml | .gitignore | */.gitignore) return 0 ;;
    AGENTS.md | CLAUDE.md | README* | package.json | pyproject.toml | requirements*.txt | .claude/settings.local.json) return 0 ;;
    src/* | app/* | tests/* | test/* | */src/* | */app/* | */tests/* | */test/*) return 0 ;;
  esac
  return 1
}

# Removes now-empty parent folders of $1, stopping at the first one that still holds anything.
prune_parents() {
  local d
  d=$(dirname "$1")
  while [ "$d" != . ] && [ "$d" != / ]; do
    rmdir "$d" 2> /dev/null || return 0
    d=$(dirname "$d")
  done
}

entries=$(read_manifest) || die "cannot parse $manifest (need jq, node or python3, and a seeded_files object)."
[ -n "$entries" ] || die "$manifest lists no seeded files."

removed=0
kept=0
blocked=0
gone=0
removed_list=""
if [ "$apply" -eq 1 ]; then verb="removed"; else verb="would remove"; fi

while IFS="$(printf '\t')" read -r path origin; do
  [ -n "$path" ] || continue
  case "$path" in
    /* | ../* | */../* | */.. | ..) printf 'remove-harness: KEEP %s: path leaves the project, not touched.\n' "$path"; kept=$((kept + 1)); blocked=$((blocked + 1)); continue ;;
  esac
  if is_protected "$path"; then
    printf 'remove-harness: KEEP %s: project file, never removed by this script.\n' "$path"
    kept=$((kept + 1))
    continue
  fi
  if [ -L "$path" ]; then
    printf 'remove-harness: KEEP %s: symbolic link, not touched.\n' "$path"
    kept=$((kept + 1))
    blocked=$((blocked + 1))
    continue
  fi
  if [ ! -e "$path" ]; then
    gone=$((gone + 1))
    continue
  fi
  if [ ! -f "$path" ]; then
    printf 'remove-harness: KEEP %s: not a regular file.\n' "$path"
    kept=$((kept + 1))
    blocked=$((blocked + 1))
    continue
  fi
  case "$origin" in
    '' | null | undefined | None | "<"*) hash_ok=2 ;;
    *) if [ "$(sha "$path")" = "$origin" ]; then hash_ok=1; else hash_ok=0; fi ;;
  esac
  if [ "$hash_ok" -ne 1 ]; then
    if [ "$hash_ok" -eq 0 ]; then why="content differs from what was seeded"; else why="no seeded hash recorded, so unchanged content cannot be proved"; fi
    if printf '%s\n' "$force" | grep -Fxq -- "$path"; then
      printf 'remove-harness: %s %s (forced; %s).\n' "$verb" "$path" "$why"
    else
      printf 'remove-harness: KEEP %s: %s. To remove it anyway: --apply --force %s\n' "$path" "$why" "$path"
      kept=$((kept + 1))
      blocked=$((blocked + 1))
      continue
    fi
  else
    printf 'remove-harness: %s %s\n' "$verb" "$path"
  fi
  removed=$((removed + 1))
  removed_list="$removed_list
$path"
  if [ "$apply" -eq 1 ]; then
    rm -f -- "$path" || die "cannot remove $path"
    rm -f -- ".claude/.harness-base/$path"
    prune_parents "$path"
    prune_parents ".claude/.harness-base/$path"
  fi
done <<EOF2
$entries
EOF2

if [ "$apply" -eq 1 ] && [ "$blocked" -eq 0 ]; then
  rm -f -- "$manifest"
  rmdir .claude/.harness-base 2> /dev/null
  rmdir .claude 2> /dev/null
  printf 'remove-harness: removed %s (no seeded file is left to remove).\n' "$manifest"
elif [ "$blocked" -gt 0 ]; then
  printf 'remove-harness: %s stays while kept files remain; run again after you deal with them.\n' "$manifest"
fi

printf 'remove-harness: %s %s file(s), kept %s, already absent %s.\n' "$verb" "$removed" "$kept" "$gone"
if [ -d .claude/review ]; then
  printf 'remove-harness: KEEP .claude/review/: generated, gitignored review records. Delete it yourself if unwanted.\n'
fi
printf 'remove-harness: by hand: the AGENTS.md tail, the .gitignore lines the scaffold added, "lefthook uninstall", and any scripts the scaffold added to package.json or pyproject.toml.\n'
if [ "$apply" -eq 0 ]; then
  printf 'remove-harness: dry run, nothing changed. Run with --apply to remove.\n'
fi

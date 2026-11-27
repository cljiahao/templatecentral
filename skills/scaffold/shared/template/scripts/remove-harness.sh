#!/usr/bin/env bash
# Removes the seeded harness listed in .claude/harness.json. Offline, read-only unless --apply is given.
# Usage: remove-harness.sh [--apply] [--force <path>]...
# Dry run by default: lists what would go and what is kept. A file whose content differs from the seeded hash is kept
# unless named with --force. Only an allow list of seeded harness locations can be removed, even with --force; every other
# manifest line (source, lockfiles, .env files, .git, docs, AGENTS.md) is kept, because the manifest is user-editable.
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
if [ ! -f "$manifest" ]; then
  printf 'remove-harness: %s is missing: the harness is already removed, or was never seeded here. Nothing to do.\n' "$manifest"
  exit 0
fi

# Prints the SHA-256 of a file.
sha() {
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

# Prints "path<TAB>origin_hash" for every seeded file; fails when any path or hash holds a control character (newline, tab, NUL).
read_manifest() {
  if command -v jq > /dev/null 2>&1; then
    jq -er '.seeded_files | to_entries[] | if ((.value.path | tostring | explode | any(. < 32)) or (.value.origin_hash | tostring | explode | any(. < 32))) then error("control character in an entry") else "\(.value.path)\t\(.value.origin_hash)" end' "$manifest"
  elif command -v node > /dev/null 2>&1; then
    node -e 'const m=JSON.parse(require("fs").readFileSync(".claude/harness.json","utf8"));for(const v of Object.values(m.seeded_files)){const a=String(v.path),b=String(v.origin_hash);if(/[\x00-\x1f]/.test(a+b))throw new Error("control character");console.log(a+"\t"+b)}'
  elif command -v python3 > /dev/null 2>&1; then
    python3 -I -c 'import json;m=json.load(open(".claude/harness.json"));[print(str(v["path"])+"\t"+str(v["origin_hash"])) if not any(ord(c)<32 for c in str(v["path"])+str(v["origin_hash"])) else (_ for _ in ()).throw(ValueError("control character")) for v in m["seeded_files"].values()]'
  else
    return 3
  fi
}

# True only for a plain relative path inside the project that names a seeded harness location.
is_removable() {
  case "$1" in
    '' | /* | .. | ../* | */.. | */../* | .git | .git/* | */.git/* | *[!A-Za-z0-9._/@+-]*) return 1 ;;
  esac
  case "$1" in
    .claude/hooks/* | .claude/agents/* | .lefthook/*) return 0 ;;
    .claude/skills/skill-audit/SKILL.md | .claude/skills/test-consolidate/SKILL.md) return 0 ;;
    .claude/ci-gates.sh | .claude/comment-hygiene-patterns.txt | .claude/gates.txt | .claude/regen-harness.sh) return 0 ;;
    .claude/registry-hosts.txt | .claude/settings.json | .claude/verify-harness.sh) return 0 ;;
    .claude/review-checklist.txt | .claude/review-checklist-stack.txt) return 0 ;;
    .claude/allowed-licences.txt | .claude/bundle-budget.txt | .claude/change-size-exclude.txt | .claude/licence-exceptions.txt) return 0 ;;
    .github/dependabot.yml | .github/workflows/ci.yml | .gitleaks.toml | .jscpd.json) return 0 ;;
    azure-pipelines.yml | azure-pipelines/templatecentral-gates.yml | lefthook.yml) return 0 ;;
    docs/harness.md | docs/adr/0001-test-each-behaviour-once.md) return 0 ;;
    scripts/check-dockerfile.sh | scripts/check-docs.sh | scripts/check-env-example.sh | scripts/check-review-record.sh) return 0 ;;
    scripts/check-comments.sh | scripts/check-comments.mjs | scripts/check-comments.py | scripts/check-comments.licences.txt) return 0 ;;
    scripts/check-duplicate-tests.sh | scripts/duplicate-tests-ts.mjs | scripts/duplicate_tests_py.py) return 0 ;;
    scripts/check-exclude-reasons.sh | scripts/check-exclude-rules.sh | scripts/check-exclude-reasons.awk) return 0 ;;
    scripts/check-exclude-reasons.mjs | scripts/check-exclude-reasons.py) return 0 ;;
    scripts/check-bundle-size.sh | scripts/check-change-size.sh | scripts/check-licences.sh | scripts/generate-sbom.sh | scripts/py-env.py) return 0 ;;
    scripts/check-secret-scanner.sh | scripts/check-supply-chain.sh | scripts/check-workflows.sh | scripts/gate-ratchet.sh) return 0 ;;
    scripts/record-review.sh | scripts/remove-harness.sh | scripts/test-budget.sh) return 0 ;;
  esac
  return 1
}

# True when the path or any parent folder of it inside the project is a symbolic link.
has_symlink_segment() {
  local rest=$1 acc=""
  while [ -n "$rest" ]; do
    case "$rest" in
      */*) acc="$acc${rest%%/*}"; rest=${rest#*/} ;;
      *) acc="$acc$rest"; rest="" ;;
    esac
    if [ -L "$acc" ]; then return 0; fi
    acc="$acc/"
  done
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
differs=0
checked=0
removed_list=""
if [ "$apply" -eq 1 ]; then verb="removed"; else verb="would remove"; fi

while IFS="$(printf '\t')" read -r path origin; do
  [ -n "$path" ] || continue
  case "$origin" in
    *"$(printf '\t')"*) printf 'remove-harness: KEEP %s: manifest line holds a tab inside a field, not trusted.\n' "$path"; kept=$((kept + 1)); continue ;;
  esac
  if ! is_removable "$path"; then
    printf 'remove-harness: KEEP %s: not a seeded harness location, so a manifest line alone cannot delete it.\n' "$path"
    kept=$((kept + 1))
    continue
  fi
  if has_symlink_segment "$path"; then
    printf 'remove-harness: KEEP %s: the file or a parent folder is a symbolic link, not touched.\n' "$path"
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
  checked=$((checked + 1))
  if [ "$hash_ok" -eq 0 ]; then differs=$((differs + 1)); fi
  if [ "$hash_ok" -ne 1 ]; then
    if [ "$hash_ok" -eq 0 ]; then why="content differs from what was seeded"; else why="no seeded hash recorded, so unchanged content cannot be proved"; fi
    nl=$'\n'
    case "$nl$force$nl" in *"$nl$path$nl"*) forced=1 ;; *) forced=0 ;; esac
    if [ "$forced" -eq 1 ]; then
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
    if ! has_symlink_segment ".claude/.harness-base/$path"; then
      rm -f -- ".claude/.harness-base/$path"
      prune_parents ".claude/.harness-base/$path"
    fi
    prune_parents "$path"
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

if [ "$checked" -gt 0 ] && [ "$differs" -eq "$checked" ]; then
  printf 'remove-harness: every seeded file reads as modified. The hashes in %s may be provisional (the scaffold re-hashes after its format pass) or the files were reformatted; compare each with its copy under .claude/.harness-base/ before using --force.\n' "$manifest"
fi
printf 'remove-harness: %s %s file(s), kept %s, already absent %s.\n' "$verb" "$removed" "$kept" "$gone"
if [ -d .claude/review ]; then
  printf 'remove-harness: KEEP .claude/review/: generated, gitignored review records. Delete it yourself if unwanted.\n'
fi
printf 'remove-harness: by hand: the AGENTS.md tail, the .gitignore lines the scaffold added, "lefthook uninstall", and any scripts the scaffold added to package.json or pyproject.toml.\n'
if [ "$apply" -eq 0 ]; then
  printf 'remove-harness: dry run, nothing changed. Run with --apply to remove.\n'
fi

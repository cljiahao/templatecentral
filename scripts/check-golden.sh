#!/usr/bin/env bash
# scripts/check-golden.sh — compare scaffold output against the golden sha256 manifests.
#
# Usage: bash scripts/check-golden.sh [--from-templates] [--golden-dir DIR] [--tree DIR] [COMBO ...]
#   COMBO is <stack>-<ci> (default: all 8 stack x ci combinations).
#   Default mode hashes the output of scripts/extract-fences.py.
#   --from-templates builds each combo by copying the template/ trees, then substituting
#   the placeholder values in tests/golden/placeholders.env, and hashes that tree.
#   --tree DIR (one COMBO) compares a generated project against the expected tree instead:
#   golden paths must exist in DIR (MISSING) and match (MISMATCH); extra files are ignored.
#   Skipped as generated at runtime: lockfiles, node_modules, shadcn output (src/components/ui/),
#   .claude/harness.json (seeded_at, origin_hash) and .claude/.harness-base/. A file whose
#   expected body holds a placeholder is only checked for existence; a file that differs
#   only in whitespace (formatter output) passes.
# Prints MISMATCH|MISSING|EXTRA <combo> <path> per difference; exit 1 if any, else 0.
# tests/golden/exceptions.txt lines (<combo|*> <path> # <reason>) suppress a path.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN_DIR="$REPO_ROOT/tests/golden"
FROM_TEMPLATES=0
TREE=""
COMBOS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-templates) FROM_TEMPLATES=1 ;;
    --golden-dir) GOLDEN_DIR="$2"; shift ;;
    --tree) TREE="$2"; shift ;;
    -*) echo "check-golden: unknown option $1" >&2; exit 2 ;;
    *) COMBOS+=("$1") ;;
  esac
  shift
done
if [[ ${#COMBOS[@]} -eq 0 ]]; then
  for stack in nextjs vite-react fastapi nestjs; do
    for ci in github azure; do COMBOS+=("$stack-$ci"); done
  done
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

sha_of() { # sha_of <file> — portable sha256
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# actual_hashes <stack> <ci> <outfile> — "<sha>  <path>" lines, sorted by path.
actual_hashes() {
  local stack="$1" ci="$2" out="$3" tree="$T/tree-$1-$2"
  if [[ $FROM_TEMPLATES -eq 0 ]]; then
    python3 "$REPO_ROOT/scripts/extract-fences.py" --stack "$stack" --ci "$ci" --out "$tree" > "$out" 2>/dev/null
    return $?
  fi
  local sk="$REPO_ROOT/skills/scaffold" ts=py
  case "$stack" in nextjs | vite-react | nestjs) ts=ts ;; esac
  local dirs=("$sk/shared/template" "$sk/shared/template-$ts" "$sk/shared/template/ci/$ci" "$sk/$stack/template")
  mkdir -p "$tree"
  local found=0 d
  for d in "${dirs[@]}"; do
    [[ -d "$d" ]] && { cp -Rp "$d/." "$tree/" && found=1; }
  done
  if [[ $found -eq 0 ]]; then echo "check-golden: no template trees for $stack-$ci" >&2; return 1; fi
  rm -rf "$tree/ci"
  if [[ -f "$GOLDEN_DIR/placeholders.env" ]]; then
    local name value
    while IFS='=' read -r name value; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      grep -rlF "__TC_${name}__" "$tree" 2>/dev/null | while IFS= read -r f; do
        python3 - "$f" "__TC_${name}__" "$value" <<'PY'
import sys
p, a, b = sys.argv[1:]
data = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8", newline="").write(data.replace(a, b))
PY
      done
    done < "$GOLDEN_DIR/placeholders.env"
  fi
  (cd "$tree" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r p; do
    printf '%s  %s\n' "$(sha_of "$p")" "$p"
  done) > "$out"
}

# excepted <combo> <path> — true if exceptions.txt lists the path for this combo or '*'.
excepted() {
  local f="$GOLDEN_DIR/exceptions.txt" line combo path
  [[ -f "$f" ]] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"
    read -r combo path <<< "$line"
    [[ -z "$combo" || -z "$path" ]] && continue
    [[ ( "$combo" == "*" || "$combo" == "$1" ) && "$path" == "$2" ]] && return 0
  done < "$f"
  return 1
}

# compare_tree <combo> <expected-tree> <generated-tree> — prints MISSING/MISMATCH lines.
compare_tree() {
  python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
combo, want, got = sys.argv[1:]
SKIP = re.compile(r"(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|node_modules/|src/components/ui/|\.claude/\.harness-base/)|^\.claude/harness\.json$")
PLACEHOLDER = re.compile(r"PROJECT_NAME_PLACEHOLDER|\[Project Name\]|__TC_[A-Z0-9_]+__")
squash = lambda b: re.sub(rb"\s+", b"", b)
bad = 0
for dirpath, _, names in os.walk(want):
    for name in sorted(names):
        full = os.path.join(dirpath, name)
        rel = os.path.relpath(full, want)
        if SKIP.search(rel):
            continue
        other = os.path.join(got, rel)
        if not os.path.isfile(other):
            print(f"MISSING {combo} {rel}"); bad = 1; continue
        a, b = open(full, "rb").read(), open(other, "rb").read()
        if a == b or PLACEHOLDER.search(a.decode("utf-8", "replace")) or squash(a) == squash(b):
            continue
        print(f"MISMATCH {combo} {rel}"); bad = 1
sys.exit(bad)
PY
}

fail=0
ok=0
for combo in "${COMBOS[@]}"; do
  golden="$GOLDEN_DIR/$combo.sha256"
  if [[ ! -f "$golden" ]]; then echo "check-golden: missing golden $golden" >&2; fail=1; continue; fi
  stack="${combo%-*}"
  ci="${combo##*-}"
  if ! actual_hashes "$stack" "$ci" "$T/actual-$combo"; then echo "check-golden: could not build $combo" >&2; fail=1; continue; fi
  if [[ -n "$TREE" ]]; then
    bad=0
    # Paths in exceptions.txt are dropped from the report, not from the comparison.
    while IFS= read -r line; do
      excepted "$combo" "${line##* }" || { echo "$line"; bad=1; }
    done < <(compare_tree "$combo" "$T/tree-$stack-$ci" "$TREE")
    if [[ $bad -eq 0 ]]; then ok=$((ok + 1)); echo "OK $combo"; else fail=1; fi
    continue
  fi
  grep -v '^#' "$golden" | grep . > "$T/want-$combo" || true
  bad=0
  # Pass 1: every golden entry. Pass 2: entries only the tree has.
  while IFS= read -r line; do
    want_sha="${line%%  *}"
    path="${line#*  }"
    got=$(grep -F -- "  $path" "$T/actual-$combo" | awk -v p="$path" '{ s=$0; sub(/^[^ ]+  /, "", s); if (s == p) { print $1; exit } }')
    excepted "$combo" "$path" && continue
    if [[ -z "$got" ]]; then echo "MISSING $combo $path"; bad=1
    elif [[ "$got" != "$want_sha" ]]; then echo "MISMATCH $combo $path"; bad=1; fi
  done < "$T/want-$combo"
  while IFS= read -r line; do
    path="${line#*  }"
    awk -v p="$path" '{ s=$0; sub(/^[^ ]+  /, "", s); if (s == p) found=1 } END { exit !found }' "$T/want-$combo" && continue
    excepted "$combo" "$path" && continue
    echo "EXTRA $combo $path"; bad=1
  done < "$T/actual-$combo"
  if [[ $bad -eq 0 ]]; then ok=$((ok + 1)); echo "OK $combo"; else fail=1; fi
done

echo "check-golden: $ok/${#COMBOS[@]} combos OK"
exit $fail

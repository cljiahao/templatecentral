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
#   Files must match byte for byte, apart from a trailing-newline difference, and:
#   - a placeholder (PROJECT_NAME_PLACEHOLDER, [Project Name], __TC_<NAME>__) matches any
#     text on one line; AGENTS.md may carry appended text; package.json may carry added deps;
#   - a file listed in tests/golden/formatter-owned.txt is compared after running its formatter
#     over both sides, and fails if the formatter is unavailable.
#   Skipped as generated at runtime: see tests/golden/exceptions.txt.
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
    --golden-dir | --tree)
      if [[ $# -lt 2 ]]; then
        echo "usage: check-golden.sh [--from-templates] [--golden-dir DIR] [--tree DIR] [COMBO ...]" >&2
        exit 2
      fi
      if [[ "$1" == "--tree" ]]; then TREE="$2"; else GOLDEN_DIR="$2"; fi
      shift ;;
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

if [[ -n "$TREE" && ${#COMBOS[@]} -ne 1 ]]; then
  echo "check-golden: --tree needs exactly one COMBO" >&2
  exit 2
fi
if [[ -n "$TREE" && $FROM_TEMPLATES -eq 1 ]]; then
  echo "check-golden: --tree and --from-templates are exclusive" >&2
  exit 2
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
  if [[ $found -eq 0 ]]; then
    echo "check-golden: no template trees for $stack-$ci; missing: ${dirs[*]}" >&2
    return 1
  fi
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
  python3 - "$1" "$2" "$3" "$GOLDEN_DIR/formatter-owned.txt" "$GOLDEN_DIR/$1.sha256" <<'PY'
import hashlib, json, os, re, subprocess, sys

combo, want, got, owned_file, golden_file = sys.argv[1:]
SKIP = re.compile(r"(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|node_modules/|src/components/ui/|\.claude/\.harness-base/)|^\.claude/harness\.json$")
PLACEHOLDER = re.compile(r"PROJECT_NAME_PLACEHOLDER|\[Project Name\]|__TC_[A-Z0-9_]+__")
APPENDED = {"AGENTS.md"}
SUBSET_JSON = {"package.json"}


def owned_rules():
    rules = []
    if os.path.isfile(owned_file):
        for line in open(owned_file, encoding="utf-8"):
            line = line.split("#", 1)[0].split()
            if len(line) == 3:
                rules.append((line[0], line[1], set(line[2].split(","))))
    return rules


RULES = owned_rules()


def formatter_for(rel):
    ext = rel.rsplit(".", 1)[-1] if "." in os.path.basename(rel) else ""
    for tool, prefix, exts in RULES:
        inside = (os.path.dirname(rel) == "") if prefix == "." else rel.startswith(prefix)
        if inside and ext in exts:
            return tool
    return None


def run_formatter(tool, rel, data):
    cmd = (["npx", "--no-install", "prettier", "--stdin-filepath", rel] if tool == "prettier"
           else ["ruff", "format", "--stdin-filename", rel, "-"])
    try:
        r = subprocess.run(cmd, input=data, capture_output=True, cwd=got, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def placeholder_regex(text, appended):
    parts, last = [], 0
    for m in PLACEHOLDER.finditer(text):
        parts.append(re.escape(text[last:m.start()]))
        parts.append(r"[^\n]+?")
        last = m.end()
    parts.append(re.escape(text[last:].rstrip("\n")))
    return "".join(parts) + (r"(?:\n.*)?" if appended else r"\n*")


def subset(a, b):
    if isinstance(a, dict):
        return isinstance(b, dict) and all(k in b and subset(v, b[k]) for k, v in a.items())
    return a == b


def package_json_ok(expect_text, actual_text):
    """The expected package.json, placeholder aside, with dependencies added and nothing else."""
    try:
        expect = json.loads(PLACEHOLDER.sub("x", expect_text))
        actual = json.loads(actual_text)
    except ValueError:
        return False
    actual["name"] = "x"
    if set(actual) != set(expect):
        return False
    return all(
        subset(v, actual[k]) if k in ("dependencies", "devDependencies") else v == actual[k]
        for k, v in expect.items()
    )


def golden_paths():
    paths = {}
    for line in open(golden_file, encoding="utf-8"):
        if line.strip() and not line.startswith("#"):
            sha, path = line.rstrip("\n").split("  ", 1)
            paths[path] = sha
    return paths


bad = 0
for rel, sha in sorted(golden_paths().items()):
    if SKIP.search(rel):
        continue
    full = os.path.join(want, rel)
    other = os.path.join(got, rel)
    # The expected tree must still be what the golden records.
    if not os.path.isfile(full) or hashlib.sha256(open(full, "rb").read()).hexdigest() != sha:
        print(f"STALE-EXPECTED {combo} {rel}"); bad = 1
    if not os.path.isfile(other):
        print(f"MISSING {combo} {rel}"); bad = 1; continue
    if not os.path.isfile(full):
        continue
    a, b = open(full, "rb").read(), open(other, "rb").read()
    if a.rstrip(b"\n") == b.rstrip(b"\n"):
        continue
    tool = formatter_for(rel)
    if tool:
        fa, fb = run_formatter(tool, rel, a), run_formatter(tool, rel, b)
        if fa is None or fb is None:
            print(f"MISMATCH {combo} {rel}"); print(f"formatter {tool} unavailable or failed for {rel}", file=sys.stderr)
            bad = 1; continue
        a, b = fa, fb
        if a.rstrip(b"\n") == b.rstrip(b"\n"):
            continue
    text = a.decode("utf-8", "replace")
    if rel in SUBSET_JSON:
        if package_json_ok(text, b.decode("utf-8", "replace")):
            continue
    elif PLACEHOLDER.search(text) or rel in APPENDED:
        if re.fullmatch(placeholder_regex(text, rel in APPENDED), b.decode("utf-8", "replace"), re.S):
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
  grep -v '^#' "$golden" | grep . > "$T/want-$combo" || true
  if [[ ! -s "$T/want-$combo" ]]; then echo "check-golden: golden $golden has no entries" >&2; fail=1; continue; fi
  if [[ ! -s "$T/actual-$combo" ]]; then echo "check-golden: no files produced for $combo" >&2; fail=1; continue; fi
  if [[ -n "$TREE" ]]; then
    bad=0
    report=$(compare_tree "$combo" "$T/tree-$stack-$ci" "$TREE")
    rc=$?
    # A path listed in exceptions.txt is dropped from the report; a crash with no report fails.
    [[ $rc -ne 0 && -z "$report" ]] && bad=1
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      excepted "$combo" "${line##* }" || { echo "$line"; bad=1; }
    done <<< "$report"
    if [[ $bad -eq 0 ]]; then ok=$((ok + 1)); echo "OK $combo"; else fail=1; fi
    continue
  fi
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

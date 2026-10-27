#!/usr/bin/env bash
# scripts/check-golden.sh — compare scaffold output against the golden sha256 manifests.
#
# Usage: bash scripts/check-golden.sh [--from-templates] [--golden-dir DIR] [--tree DIR] [COMBO ...]
#   COMBO is <stack>-<ci> (default: all 8 stack x ci combinations).
#   Default mode hashes the output of scripts/extract-fences.py plus the template trees:
#   a path held in a template tree comes from the templates, every other path from the
#   fences, and a path produced by both fails as DUPLICATE (its fence is still in the markdown).
#   --from-templates builds each combo from the template trees alone (shared/template,
#   shared/template-<ts|py>, shared/template-ci/<github-<ts|py>|azure>, <stack>/template),
#   substitutes the placeholder values in tests/golden/placeholders.env, and compares only
#   the golden paths those trees hold: a path no template holds yet is still a fence, and the
#   default mode fails it as MISSING if neither source produces it.
#   --tree DIR (one COMBO) compares a generated project against the expected tree instead:
#   golden paths must exist in DIR (MISSING) and match (MISMATCH); extra files are ignored.
#   Files must match byte for byte, apart from a trailing-newline difference, and:
#   - a placeholder (PROJECT_NAME_PLACEHOLDER, [Project Name], __TC_<NAME>__) matches any
#     text on one line; AGENTS.md may carry appended text; package.json may carry added deps;
#   - a file listed in tests/golden/formatter-owned.txt is compared after running its formatter
#     over both sides, and fails if the formatter is unavailable.
#   Skipped as generated at runtime: see tests/golden/exceptions.txt.
#   File modes are not compared: the golden records content hashes only, and a checkout can change
#   modes (umask, a Windows working tree). The exec bits of the template scripts are checked against
#   template.manifest by test-template-copy.sh and lint-skills.sh instead.
# A path in tests/golden/exceptions.txt suppresses STALE-EXPECTED, MISSING, MISMATCH and EXTRA
# for that path.
# Prints MISMATCH|MISSING|EXTRA <combo> <path> per difference; exit 1 if any, else 0.
# tests/golden/exceptions.txt lines (<combo|*> <path> # <reason>) suppress a path.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# TC_SCAFFOLD_DIR and TC_EXTRACT point the check at test fixtures; they are read only when TC_TEST=1,
# so a stray variable in a CI environment cannot redirect the real check.
SCAFFOLD_DIR="$REPO_ROOT/skills/scaffold"
[[ "${TC_TEST:-}" == 1 && -n "${TC_SCAFFOLD_DIR:-}" ]] && SCAFFOLD_DIR="$TC_SCAFFOLD_DIR"
GOLDEN_DIR="$REPO_ROOT/tests/golden"
FROM_TEMPLATES=0
TREE=""
COMBOS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-templates) FROM_TEMPLATES=1 ;;
    -h | --help)
      echo "Usage: check-golden.sh [--from-templates] [--golden-dir DIR] [--tree DIR] [COMBO ...]"
      echo "  COMBO is <stack>-<ci>: stack nextjs, vite-react, fastapi or nestjs; ci github or azure."
      exit 0 ;;
    --golden-dir | --tree)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
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
for combo in ${COMBOS[@]+"${COMBOS[@]}"}; do
  case "$combo" in
    nextjs-github | nextjs-azure | vite-react-github | vite-react-azure | fastapi-github | fastapi-azure | nestjs-github | nestjs-azure) ;;
    *) echo "check-golden: unknown combo $combo (want <stack>-<ci>, see --help)" >&2; exit 2 ;;
  esac
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

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

sha_of() { # sha_of <file> — portable sha256
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# template_dirs <stack> <ci> — the template trees one combo copies, in copy order.
template_dirs() {
  local stack="$1" ci="$2" ts=py ci_dir=azure
  case "$stack" in nextjs | vite-react | nestjs) ts=ts ;; esac
  [[ "$ci" == github ]] && ci_dir="github-$ts"
  printf '%s\n' "$SCAFFOLD_DIR/shared/template" "$SCAFFOLD_DIR/shared/template-$ts" \
    "$SCAFFOLD_DIR/shared/template-ci/$ci_dir" "$SCAFFOLD_DIR/$stack/template"
}

# overlay_templates <stack> <ci> <tree> — copy the combo's template trees into <tree>; prints
# the relative path of every file copied; returns 1 when no template tree exists.
overlay_templates() {
  local d found=1
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    (cd "$d" && find . -type f | sed 's|^\./||') >> "$T/overlaid"
    mkdir -p "$3" && cp -Rp "$d/." "$3/" && found=0
  done < <(template_dirs "$1" "$2")
  return $found
}

# expected_template_count <stack> <ci> — files the manifests list for one combo: the shared manifest
# rows for its trees (template, template-<ts|py>, template-ci/<host>) plus every row of
# <stack>/template.manifest when that exists.
expected_template_count() {
  local stack="$1" ci="$2" ts=py ci_dir=azure n=0 m
  case "$stack" in nextjs | vite-react | nestjs) ts=ts ;; esac
  [[ "$ci" == github ]] && ci_dir="github-$ts"
  m="$SCAFFOLD_DIR/shared/template.manifest"
  if [[ -f "$m" ]]; then
    n=$(awk -v a="template/" -v b="template-$ts/" -v c="template-ci/$ci_dir/" \
      '!/^#/ && NF && (index($1, a) == 1 || index($1, b) == 1 || index($1, c) == 1) { n++ } END { print n + 0 }' "$m")
  fi
  m="$SCAFFOLD_DIR/$stack/template.manifest"
  if [[ -f "$m" ]]; then n=$((n + $(awk '!/^#/ && NF { n++ } END { print n + 0 }' "$m"))); fi
  echo "$n"
}

# actual_hashes <stack> <ci> <outfile> — "<sha>  <path>" lines, sorted by path.
actual_hashes() {
  local stack="$1" ci="$2" out="$3" tree="$T/tree-$1-$2"
  : > "$T/overlaid"
  if [[ $FROM_TEMPLATES -eq 0 ]]; then
    local extract=(python3 "$REPO_ROOT/scripts/extract-fences.py")
    # TC_EXTRACT replaces the extractor command (split on spaces); tests use it to simulate a failure.
    [[ "${TC_TEST:-}" == 1 && -n "${TC_EXTRACT:-}" ]] && read -r -a extract <<< "$TC_EXTRACT"
    if ! "${extract[@]}" --stack "$stack" --ci "$ci" --out "$tree" > "$out" 2> "$T/extract-$stack-$ci.err"; then
      echo "check-golden: extract-fences failed for $stack-$ci:" >&2
      cat "$T/extract-$stack-$ci.err" >&2
      return 1
    fi
    mkdir -p "$tree"
    local before="$T/fenced-$stack-$ci"
    (cd "$tree" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$before"
    overlay_templates "$stack" "$ci" "$tree" || true
    LC_ALL=C sort -u "$T/overlaid" | comm -12 "$before" - | while IFS= read -r p; do echo "DUPLICATE $stack-$ci $p"; done > "$T/dups-$stack-$ci"
  else
    mkdir -p "$tree"
    if ! overlay_templates "$stack" "$ci" "$tree"; then
      echo "check-golden: no template trees for $stack-$ci; missing: $(template_dirs "$stack" "$ci" | tr '\n' ' ')" >&2
      return 1
    fi
    rm -f "$T/dups-$stack-$ci"
  fi
  if [[ -f "$GOLDEN_DIR/placeholders.env" ]]; then
    local name value
    while IFS='=' read -r name value || [[ -n "$name" ]]; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      if [[ "$name" == *[[:space:]]* || -z "$value" ]]; then
        echo "check-golden: placeholders.env line must be NAME=value, got: $name${value:+=$value}" >&2
        return 1
      fi
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
import hashlib, json, os, re, subprocess, sys, traceback


def crash(kind, value, tb):
    traceback.print_exception(kind, value, tb)
    os._exit(3)


# Exit 1 means differences were reported; any other nonzero exit is a crash and never an OK.
sys.excepthook = crash

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
compared = 0
golden = golden_paths()
reported = set()


def symlink_in_chain(rel):
    """The first directory above rel (from the top) that is a symlink in the project, or None."""
    parts = rel.split("/")[:-1]
    for n in range(1, len(parts) + 1):
        d = "/".join(parts[:n])
        if os.path.islink(os.path.join(got, d)):
            return d
    return None


def report_symlink(path):
    global bad
    if path not in reported:
        reported.add(path)
        print(f"SYMLINK {combo} {path}")
        bad = 1

for rel, sha in sorted(golden.items()):
    if SKIP.search(rel):
        continue
    compared += 1
    full = os.path.join(want, rel)
    other = os.path.join(got, rel)
    # The expected tree must still be what the golden records.
    if not os.path.isfile(full) or hashlib.sha256(open(full, "rb").read()).hexdigest() != sha:
        print(f"STALE-EXPECTED {combo} {rel}"); bad = 1
    link = symlink_in_chain(rel)
    if link:
        report_symlink(link); continue
    if os.path.islink(other):
        report_symlink(rel); continue
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
if compared == 0:
    print(f"EMPTY {combo} no golden path was compared"); bad = 1
# The enforcement-layer directories hold only seeded files: a hook or git-hook script that is not in the
# golden was added from outside the scaffold. hooks/local/ is where a project keeps its own guards.
for top in (".claude/hooks", ".lefthook"):
    if os.path.islink(os.path.join(got, top)):
        report_symlink(top)
    for dp, ds, fs in os.walk(os.path.join(got, top)):
        for d in ds:
            if os.path.islink(os.path.join(dp, d)):
                report_symlink(os.path.relpath(os.path.join(dp, d), got))
        for f in fs:
            rel = os.path.relpath(os.path.join(dp, f), got)
            if rel not in golden and not rel.startswith(".claude/hooks/local/"):
                print(f"EXTRA {combo} {rel}"); bad = 1
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
  if [[ -s "$T/dups-$stack-$ci" ]]; then
    while IFS= read -r line; do excepted "$combo" "${line##* }" || { echo "$line"; fail=1; }; done < "$T/dups-$stack-$ci"
  fi
  if [[ -n "$TREE" ]]; then
    bad=0
    report=$(compare_tree "$combo" "$T/tree-$stack-$ci" "$TREE")
    rc=$?
    # A path listed in exceptions.txt is dropped from the report. Exit 0 and exit 1 (differences
    # reported) are the only valid results: any other exit is a crash and fails, whatever was printed
    # before it, and a report line that is not a difference is never exceptable.
    if [[ $rc -gt 1 ]]; then echo "check-golden: compare of $combo crashed (exit $rc)" >&2; bad=1; fi
    [[ $rc -eq 1 && -z "$report" ]] && bad=1
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      case "$line" in
        MISSING\ * | MISMATCH\ * | STALE-EXPECTED\ * | SYMLINK\ * | EXTRA\ *) excepted "$combo" "${line##* }" || { echo "$line"; bad=1; } ;;
        *) echo "$line"; bad=1 ;;
      esac
    done <<< "$report"
    if [[ $bad -eq 0 ]]; then ok=$((ok + 1)); echo "OK $combo"; else fail=1; fi
    continue
  fi
  bad=0
  covered=0
  # Pass 1: every golden entry. Pass 2: entries only the tree has.
  while IFS= read -r line; do
    want_sha="${line%%  *}"
    path="${line#*  }"
    got=$(grep -F -- "  $path" "$T/actual-$combo" | P="$path" awk '{ s=$0; sub(/^[^ ]+  /, "", s); if (s == ENVIRON["P"]) { print $1; exit } }')
    [[ -n "$got" ]] && covered=$((covered + 1))
    excepted "$combo" "$path" && continue
    if [[ -z "$got" && $FROM_TEMPLATES -eq 1 ]]; then continue
    elif [[ -z "$got" ]]; then echo "MISSING $combo $path"; bad=1
    elif [[ "$got" != "$want_sha" ]]; then echo "MISMATCH $combo $path"; bad=1; fi
  done < "$T/want-$combo"
  while IFS= read -r line; do
    path="${line#*  }"
    P="$path" awk '{ s=$0; sub(/^[^ ]+  /, "", s); if (s == ENVIRON["P"]) found=1 } END { exit !found }' "$T/want-$combo" && continue
    excepted "$combo" "$path" && continue
    echo "EXTRA $combo $path"; bad=1
  done < "$T/actual-$combo"
  if [[ $FROM_TEMPLATES -eq 1 ]]; then
    # The trees must hold every file the manifests list, so deleting a template file fails here
    # even though a path no template holds yet is skipped above.
    expected=$(expected_template_count "$stack" "$ci")
    if [[ "$expected" -eq 0 || "$covered" -ne "$expected" ]]; then
      echo "COUNT $combo templated $covered expected $expected"; bad=1
    fi
  fi
  if [[ $bad -eq 0 ]]; then
    ok=$((ok + 1))
    if [[ $FROM_TEMPLATES -eq 1 ]]; then echo "OK $combo ($covered of $(wc -l < "$T/want-$combo" | tr -d ' ') golden paths templated)"; else echo "OK $combo"; fi
  else fail=1; fi
done

echo "check-golden: $ok/${#COMBOS[@]} combos OK"
exit $fail

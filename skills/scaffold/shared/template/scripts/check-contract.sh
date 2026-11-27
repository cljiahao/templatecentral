#!/usr/bin/env bash
# API contract gate: the OpenAPI document the code produces must equal the committed openapi.json, so a change to a route cannot leave the contract behind.
# fastapi and nestjs: the generator is fixed by the stack, never read from a file a change can edit unnoticed. fastapi runs "python3 -I scripts/export-openapi.py", nestjs runs "node scripts/export-openapi.mjs", from the app folder; each writes the document to stdout, offline, with no server on a port. The project owns those two entry points (the scaffold does not seed them yet).
# The app may sit in any folder (backend/, apps/api/): it is found by its stack files (requirements*.txt or pyproject.toml naming fastapi, nest-cli.json or @nestjs/core in package.json) or by its entry point, anywhere in the tracked and untracked-but-not-ignored files. The gate works from the repository root, so a run from a subfolder gives the same result.
# Comparison: both documents are read with the stack's interpreter (python3 -I, node), keys sorted at every level, whitespace dropped, array order kept. A difference fails, prints at most 40 lines of unified diff and the exact regenerate command. A document that differs only in key order or whitespace passes.
# Fails closed: a committed contract that is empty, not a JSON object with an openapi or swagger key, a symlink, not a regular file or over 5 MB; a generator that exits non-zero, prints nothing or prints invalid JSON; a committed contract with no entry point; an entry point with no committed contract; a missing python3 or node (one line, in every mode).
# Base ref (argument, GATE_BASE, else origin/main) is read for one rule: when the entry point and the contract both changed in the same diff, the gate fails, because a changed generator can print the committed file. A changed entry point alone is reported. An unresolved base is a failure in CI and skips that one rule locally.
# Nothing checked (exit 0, own line): an app with no committed contract and no entry point; a frontend (next.config.*, vite.config.*), because the scaffold seeds no generated API types from a contract today. No generator is added here.
# Exit: 0 match or nothing checked, 1 a mismatch or a rule broken, 2 it could not run (no git, unreadable input, unresolved base in CI, no temporary folder).
# Not caught: a developer who edits files outside git and the hooks on their own machine and never opens a PR; git commit --no-verify locally (CI still runs the gate); a contract that matches the code but is wrong for the consumer; an entry point that prints the committed file and was changed in an earlier pull request; a generator that reaches a network; stacks or tools the plugin does not seed.
# Usage: bash scripts/check-contract.sh [base-ref]        Env: GATE_BASE.
set -uo pipefail
export LC_ALL=C
# Every git call reads a path literally, so a file name that looks like pathspec magic is a plain name.
export GIT_LITERAL_PATHSPECS=1

MAX_BYTES=5242880
tab=$(printf '\t')

die() {
  printf 'check-contract: %s\n' "$1" >&2
  exit 2
}

# True in GitHub Actions, Azure Pipelines or any run that sets CI.
is_ci() {
  case "${CI:-}" in '' | [Ff][Aa][Ll][Ss][Ee] | 0) ;; *) return 0 ;; esac
  case "${GITHUB_ACTIONS:-}${TF_BUILD:-}" in *[Tt][Rr][Uu][Ee]*) return 0 ;; esac
  return 1
}

failed=0
checked=0
# Prints a failure line and marks the run failed, so every broken rule shows in one run.
fail() {
  printf 'check-contract: FAIL: %s\n' "$1" >&2
  failed=1
}

command -v git > /dev/null 2>&1 || die "git is not installed"
top=$(git rev-parse --show-toplevel 2> /dev/null) || die "not a git repository"
cd "$top" || die "cannot enter $top"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-contract.XXXXXX") || die "cannot create a temporary folder in ${TMPDIR:-/tmp}"
trap 'rm -rf "$tmp"' EXIT

base=${1:-${GATE_BASE:-origin/main}}
mb=
if git rev-parse --verify --quiet "${base}^{commit}" > /dev/null 2>&1; then
  mb=$(git merge-base "$base" HEAD 2> /dev/null) || mb=
fi
if [ -z "$mb" ]; then
  if is_ci; then
    die "base ref '$base' not found or has no merge base with HEAD, so a changed generator cannot be detected. Fetch it (git fetch origin main with full history) or pass another base ref."
  fi
  echo "check-contract: base ref '$base' not found: the changed-generator rule is skipped locally."
fi

# Writes the helper scripts: one prints the canonical form of a JSON file, one per interpreter.
cat > "$tmp/norm.py" << 'PY_NORM' || die "cannot write the python helper"
import json
import sys


def refuse(const):
    raise ValueError("non-finite number " + const)


with open(sys.argv[1], encoding="utf-8") as fh:
    text = fh.read()
if text.strip() == "":
    sys.stderr.write("empty\n")
    sys.exit(3)
try:
    doc = json.loads(text, parse_constant=refuse)
except ValueError as e:
    sys.stderr.write("not valid JSON: " + str(e) + "\n")
    sys.exit(3)
if not isinstance(doc, dict) or not ("openapi" in doc or "swagger" in doc):
    sys.stderr.write("not a JSON object with an openapi or swagger key\n")
    sys.exit(3)
sys.stdout.write(json.dumps(doc, sort_keys=True, indent=2, ensure_ascii=False) + "\n")
PY_NORM
cat > "$tmp/norm.mjs" << 'NODE_NORM' || die "cannot write the node helper"
import { readFileSync } from "node:fs";

const text = readFileSync(process.argv[2], "utf8");
if (text.trim() === "") { process.stderr.write("empty\n"); process.exit(3); }
let doc;
try { doc = JSON.parse(text); } catch (e) { process.stderr.write("not valid JSON: " + e.message + "\n"); process.exit(3); }
if (doc === null || typeof doc !== "object" || Array.isArray(doc) || !("openapi" in doc || "swagger" in doc)) {
  process.stderr.write("not a JSON object with an openapi or swagger key\n");
  process.exit(3);
}
const sort = (v) => Array.isArray(v) ? v.map(sort) : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sort(v[k])])) : v;
process.stdout.write(JSON.stringify(sort(doc), null, 2) + "\n");
NODE_NORM

# Collects facts about every folder from the file list: "dir<TAB>kind" lines for the stack files, the entry points and the contract.
: > "$tmp/facts.txt"
git -c core.quotepath=false ls-files -z --cached --others --exclude-standard > "$tmp/all.z" 2> "$tmp/err.txt" || die "git ls-files failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"

# Counts whole-word, case-insensitive matches of $1 in file $2.
count_word() {
  local n
  n=$(grep -a -i -w -c -e "$1" -- "$2" 2> "$tmp/err.txt")
  if [ $? -gt 1 ]; then die "cannot read $2: $(head -n 1 "$tmp/err.txt")"; fi
  echo "$n"
}
# Counts fixed-string matches of $1 in file $2.
count_fixed() {
  local n
  n=$(grep -a -F -c -e "$1" -- "$2" 2> "$tmp/err.txt")
  if [ $? -gt 1 ]; then die "cannot read $2: $(head -n 1 "$tmp/err.txt")"; fi
  echo "$n"
}

while IFS= read -r -d '' p; do
  case "$p" in *$'\n'*) die "a file name holds a line break: refusing to read it" ;; esac
  d=$(dirname "$p")
  b=${p##*/}
  case "$b" in
    requirements.txt | requirements-dev.txt | pyproject.toml)
      if [ -f "$p" ] && [ "$(count_word fastapi "$p")" -gt 0 ]; then printf '%s\tfast\n' "$d" >> "$tmp/facts.txt"; fi
      ;;
    nest-cli.json) printf '%s\tnest\n' "$d" >> "$tmp/facts.txt" ;;
    package.json)
      if [ -f "$p" ] && [ "$(count_fixed '"@nestjs/core"' "$p")" -gt 0 ]; then printf '%s\tnest\n' "$d" >> "$tmp/facts.txt"; fi
      ;;
    next.config.* | vite.config.*) printf '%s\tfront\n' "$d" >> "$tmp/facts.txt" ;;
    openapi.json) printf '%s\tcontract\n' "$d" >> "$tmp/facts.txt" ;;
    export-openapi.py) case "$p" in */scripts/export-openapi.py | scripts/export-openapi.py) printf '%s\tgenpy\n' "$(dirname "$d")" >> "$tmp/facts.txt" ;; esac ;;
    export-openapi.mjs) case "$p" in */scripts/export-openapi.mjs | scripts/export-openapi.mjs) printf '%s\tgenmjs\n' "$(dirname "$d")" >> "$tmp/facts.txt" ;; esac ;;
  esac
done < "$tmp/all.z"
sort -u "$tmp/facts.txt" > "$tmp/facts.sorted" || die "cannot sort the facts"
mv "$tmp/facts.sorted" "$tmp/facts.txt" || die "cannot update the facts"

# True when folder $1 has fact $2.
has_fact() {
  local n
  n=$(grep -c -F -x -e "$1$tab$2" -- "$tmp/facts.txt" 2> "$tmp/err.txt")
  if [ $? -gt 1 ]; then die "cannot read the facts: $(head -n 1 "$tmp/err.txt")"; fi
  [ "$n" -gt 0 ]
}

# Prints the path of $2 inside folder $1 (no ./ prefix at the root).
at() {
  if [ "$1" = . ]; then printf '%s' "$2"; else printf '%s/%s' "$1" "$2"; fi
}

# True when the file at path $1 differs from its merge base copy, or is new. Needs $mb.
changed_vs_base() {
  if ! git cat-file -e "$mb:$1" 2> /dev/null; then return 0; fi
  git show "$mb:$1" > "$tmp/base-file" 2> "$tmp/err.txt" || die "cannot read $1 at the merge base: $(head -n 1 "$tmp/err.txt")"
  ! cmp -s "$tmp/base-file" "$1"
}

# Runs the stack's interpreter with its flags: python3 -I for fastapi, node for nestjs.
run_interp() {
  if [ "$stack" = fastapi ]; then "$interp" -I "$@"; else "$interp" "$@"; fi
}

# Checks one app folder $1 of stack $2 (fastapi or nestjs).
check_app() {
  local dir=$1 stack=$2 gen interp norm contract genfile regen label
  contract=$(at "$dir" openapi.json)
  label=$dir
  [ "$dir" = . ] && label='the repository root'
  if [ "$stack" = fastapi ]; then
    gen=scripts/export-openapi.py
    interp=python3
    norm=$tmp/norm.py
    if [ -x "$top/$(at "$dir" .venv/bin/python3)" ]; then interp="$top/$(at "$dir" .venv/bin/python3)"; fi
  else
    gen=scripts/export-openapi.mjs
    interp=node
    norm=$tmp/norm.mjs
  fi
  genfile=$(at "$dir" "$gen")
  local have_contract=0 have_gen=0
  if [ -e "$contract" ] || [ -L "$contract" ]; then have_contract=1; fi
  if [ -f "$genfile" ]; then have_gen=1; fi
  if [ "$have_contract" -eq 0 ] && [ "$have_gen" -eq 0 ]; then
    echo "check-contract: nothing checked: $label ($stack) has no committed openapi.json and no $gen."
    return
  fi
  if [ "$stack" = fastapi ]; then
    regen="cd $(printf '%q' "$dir") && python3 -I $gen > openapi.json"
  else
    regen="cd $(printf '%q' "$dir") && node $gen > openapi.json"
  fi
  if [ "$have_gen" -eq 0 ]; then
    fail "$label ($stack): $contract is committed and $gen does not exist, so the contract cannot be generated from the code. Add the entry point: it prints the OpenAPI document to stdout, offline."
    return
  fi
  if [ "$have_contract" -eq 0 ]; then
    fail "$label ($stack): $gen exists and no $contract is committed. Generate and commit it: $regen"
    return
  fi
  if ! command -v "$interp" > /dev/null 2>&1; then
    fail "$label ($stack): $(basename "$interp") is not installed, so the contract cannot be compared. Install it."
    return
  fi
  if [ -L "$contract" ] || [ ! -f "$contract" ]; then
    fail "$label ($stack): $contract is a symlink or not a regular file. Commit the document itself."
    return
  fi
  local size
  size=$(wc -c < "$contract") || die "cannot read $contract"
  size=${size//[!0-9]/}
  if [ "$size" -gt "$MAX_BYTES" ]; then
    fail "$label ($stack): $contract is $size bytes, over the $MAX_BYTES limit."
    return
  fi
  if [ "$size" -eq 0 ]; then
    fail "$label ($stack): $contract is empty."
    return
  fi
  if [ -n "$mb" ] && changed_vs_base "$genfile"; then
    if changed_vs_base "$contract"; then
      fail "$label ($stack): $genfile and $contract both changed in this diff. A changed generator can print the committed file, so review the generator change on its own, then change the contract in a later pull request."
    else
      echo "check-contract: notice: $genfile changed in this diff, review it: the comparison trusts it."
    fi
  fi
  run_interp "$norm" "$contract" > "$tmp/committed.json" 2> "$tmp/err.txt" || {
    fail "$label ($stack): $contract is invalid: $(head -n 1 "$tmp/err.txt")"
    return
  }
  (cd "$dir" && run_interp "$gen") > "$tmp/generated-raw.json" 2> "$tmp/gen-err.txt"
  local gec=$?
  if [ "$gec" -ne 0 ]; then
    fail "$label ($stack): $gen exited $gec: $(tail -n 3 "$tmp/gen-err.txt" | tr '\n' ' ')"
    return
  fi
  if [ ! -s "$tmp/generated-raw.json" ]; then
    fail "$label ($stack): $gen exited 0 and printed nothing, so no document was generated."
    return
  fi
  run_interp "$norm" "$tmp/generated-raw.json" > "$tmp/generated.json" 2> "$tmp/err.txt" || {
    fail "$label ($stack): $gen printed an invalid document: $(head -n 1 "$tmp/err.txt")"
    return
  }
  checked=$((checked + 1))
  if ! cmp -s "$tmp/committed.json" "$tmp/generated.json"; then
    diff -u --label committed --label generated "$tmp/committed.json" "$tmp/generated.json" > "$tmp/diff.txt" 2> "$tmp/err.txt"
    if [ $? -gt 1 ]; then die "diff failed"; fi
    fail "$label ($stack): $contract does not match the document the code generates. The first 40 lines of the difference (- committed, + generated):"
    sed -n '1,40p' "$tmp/diff.txt" | sed 's/^/check-contract:   | /' >&2
    printf 'check-contract: regenerate with: %s\n' "$regen" >&2
    return
  fi
}

cut -f1 "$tmp/facts.txt" | sort -u > "$tmp/dirs.txt" || die "cannot list the folders"
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  fast=0
  nest=0
  front=0
  has_fact "$dir" fast && fast=1
  has_fact "$dir" nest && nest=1
  has_fact "$dir" front && front=1
  stack=
  if [ "$fast" -eq 1 ] && [ "$nest" -eq 1 ]; then
    fail "$dir: both a fastapi and a nestjs stack file sit in this folder, so the generator cannot be chosen. Split the apps into separate folders."
    continue
  fi
  if [ "$fast" -eq 1 ]; then stack=fastapi; fi
  if [ "$nest" -eq 1 ]; then stack=nestjs; fi
  if [ -z "$stack" ]; then
    gp=0
    gm=0
    has_fact "$dir" genpy && gp=1
    has_fact "$dir" genmjs && gm=1
    if [ "$gp" -eq 1 ] && [ "$gm" -eq 0 ]; then stack=fastapi; fi
    if [ "$gm" -eq 1 ] && [ "$gp" -eq 0 ]; then stack=nestjs; fi
  fi
  if [ -n "$stack" ]; then
    check_app "$dir" "$stack"
    continue
  fi
  if [ "$front" -eq 1 ]; then
    echo "check-contract: nothing checked: $dir is a frontend and the scaffold seeds no generated API types from a contract."
    continue
  fi
  if has_fact "$dir" contract; then
    fail "$dir: $(at "$dir" openapi.json) is committed and no stack or entry point says how to generate it. Add scripts/export-openapi.py (fastapi) or scripts/export-openapi.mjs (nestjs)."
  fi
done < "$tmp/dirs.txt"

if [ "$failed" -eq 1 ]; then
  exit 1
fi
if [ "$checked" -eq 0 ]; then
  if [ ! -s "$tmp/dirs.txt" ]; then
    echo "check-contract: nothing checked: no fastapi or nestjs app, no entry point and no committed openapi.json found."
  fi
  exit 0
fi
echo "check-contract: ok ($checked contract(s) match the code)"

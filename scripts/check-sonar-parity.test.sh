#!/usr/bin/env bash
# scripts/check-sonar-parity.test.sh — tests for scripts/check-sonar-parity.sh on a scratch copy of the configs it reads.
# Usage: bash scripts/check-sonar-parity.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-sonar-parity.sh"
SC="skills/scaffold"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/sp.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# row <lang> <key> <type> <status> <local> <reason>
row() { printf '%s\t%s\tname\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6"; }

# fresh_root <name>: a scratch root holding the presets, the four configs and the gate files the control table reads.
fresh_root() {
  R="$T/$1"
  rm -rf "$R"
  mkdir -p "$R/scripts"
  cp -R "$REPO_ROOT/scripts/sonar-parity-presets" "$R/scripts/"
  local f
  for f in nextjs/template/eslint.config.mjs vite-react/template/eslint.config.mjs nestjs/template/eslint.config.mjs \
    fastapi/template/pyproject.toml shared/template-ts/.jscpd.json shared/template-py/.jscpd.json \
    shared/template/scripts/gate-ratchet.sh; do
    mkdir -p "$R/$SC/$(dirname "$f")"
    cp "$REPO_ROOT/$SC/$f" "$R/$SC/$f"
  done
}

# control table: every row passes against the real configs.
control() {
  row ts typescript:S3776 "code smell" covered sonarjs/cognitive-complexity ""
  row ts typescript:CTRL1 "code smell" covered no-warning-comments ""
  row ts typescript:CTRL2 "code smell" not-covered - "needs type information"
  row ts quality-gate:dup "quality gate" partial 'gate:template-ts/.jscpd.json#"threshold": 3' "whole source, not new code only"
  row ts quality-gate:script "quality gate" covered gate:template/scripts/gate-ratchet.sh ""
  row py python:S3776 "code smell" partial C901 "cyclomatic, not cognitive"
  row py python:S1481 "code smell" covered F841 ""
  row py python:S2068 "security hotspot" partial S105,S106 "name based"
  row py python:S100 "code smell" not-covered - "pep8-naming is not selected"
}

# run <table-file>: sets OUT and EC.
run() {
  OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$CHECK" --root "$R" --table "$1" 2>&1)
  EC=$?
}

# --- clean control
fresh_root clean
control > "$T/control.tsv"
run "$T/control.tsv"
check 0 "$EC" "control table passes"
has "ts: covered 3, partial 1, not-covered 1" "$OUT" "control summary ts"
has "py: covered 1, partial 2, not-covered 1" "$OUT" "control summary py"
has "not-covered typescript:CTRL2: needs type information" "$OUT" "not-covered rows are listed with reasons"

# --- table errors
{ control; row ts typescript:S3776 "code smell" covered sonarjs/cognitive-complexity ""; } > "$T/dup.tsv"
run "$T/dup.tsv"
check 1 "$EC" "duplicate key fails"
has "duplicate of line" "$OUT" "duplicate key message"

{ control; row ts typescript:CTRL3 "code smell" partial no-warning-comments ""; } > "$T/noreason.tsv"
run "$T/noreason.tsv"
check 1 "$EC" "partial row without reason fails"
has "typescript:CTRL3" "$OUT" "missing reason names the row"
has "needs a reason" "$OUT" "missing reason message"

{ control; row ts typescript:CTRL4 "code smell" not-covered - ""; } > "$T/noreason2.tsv"
run "$T/noreason2.tsv"
check 1 "$EC" "not-covered row without reason fails"

{ control; row ts typescript:CTRL5 "code smell" covered - ""; } > "$T/nolocal.tsv"
run "$T/nolocal.tsv"
check 1 "$EC" "covered row without a local rule fails"
has "needs a local rule id" "$OUT" "missing local rule message"

{ control; row ts typescript:CTRL6 "code smell" maybe no-warning-comments ""; } > "$T/badstatus.tsv"
run "$T/badstatus.tsv"
check 1 "$EC" "invalid status fails"

# --- a covered row whose rule is absent from one stack's config
fresh_root absent
awk '!/no-warning-comments/' "$R/$SC/vite-react/template/eslint.config.mjs" > "$R/x" && mv "$R/x" "$R/$SC/vite-react/template/eslint.config.mjs"
run "$T/control.tsv"
check 1 "$EC" "rule missing from one stack fails"
has "typescript:CTRL1" "$OUT" "absent rule names the row"
has "not set in vite-react" "$OUT" "absent rule names the stack"

# --- a rule set to warn instead of error
fresh_root warn
sed "s/'no-warning-comments': \['error'/'no-warning-comments': ['warn'/" "$R/$SC/nestjs/template/eslint.config.mjs" > "$R/x" && mv "$R/x" "$R/$SC/nestjs/template/eslint.config.mjs"
run "$T/control.tsv"
check 1 "$EC" "rule at warn fails"
has "is warn in nestjs" "$OUT" "warn names the stack"

# --- a preset rule turned off by the config
fresh_root off
sed "s/'sonarjs\/cognitive-complexity': \['error', 15\]/'sonarjs\/cognitive-complexity': 'off'/" "$R/$SC/nextjs/template/eslint.config.mjs" > "$R/x" && mv "$R/x" "$R/$SC/nextjs/template/eslint.config.mjs"
run "$T/control.tsv"
check 1 "$EC" "preset rule turned off fails"
has "is off in nextjs" "$OUT" "off names the stack"

# --- a config form the reader cannot resolve fails the row that needs it
fresh_root unresolved
sed "s/'no-warning-comments': \['error'/'no-warning-comments': [level/" "$R/$SC/nextjs/template/eslint.config.mjs" > "$R/x" && mv "$R/x" "$R/$SC/nextjs/template/eslint.config.mjs"
run "$T/control.tsv"
check 1 "$EC" "unresolvable config fails closed"
has "cannot resolve nextjs eslint config statically" "$OUT" "unresolved message names the stack"
has "typescript:" "$OUT" "unresolved message names a row"

# --- ruff: code removed from select, and code added to ignore
fresh_root ruff
sed 's/"C901", //' "$R/$SC/fastapi/template/pyproject.toml" > "$R/x" && mv "$R/x" "$R/$SC/fastapi/template/pyproject.toml"
run "$T/control.tsv"
check 1 "$EC" "ruff code missing from select fails"
has "ruff C901 is not enabled" "$OUT" "ruff message names the code"

fresh_root ruffignore
sed 's/^\[tool.ruff.lint\]$/[tool.ruff.lint]\nignore = ["F841"]/' "$R/$SC/fastapi/template/pyproject.toml" > "$R/x" && mv "$R/x" "$R/$SC/fastapi/template/pyproject.toml"
run "$T/control.tsv"
check 1 "$EC" "ruff code in ignore fails"
has "ruff F841 is not enabled" "$OUT" "ignored code is named"

# --- gate script missing
fresh_root gate
rm "$R/$SC/shared/template/scripts/gate-ratchet.sh"
run "$T/control.tsv"
check 1 "$EC" "missing gate script fails"
has "gate file missing: template/scripts/gate-ratchet.sh" "$OUT" "missing gate message"

fresh_root gateneedle
sed 's/"threshold": 3/"threshold": 9/' "$R/$SC/shared/template-ts/.jscpd.json" > "$R/x" && mv "$R/x" "$R/$SC/shared/template-ts/.jscpd.json"
run "$T/control.tsv"
check 1 "$EC" "gate file without its literal fails"
has "does not contain" "$OUT" "needle message"

# --- sonarjs key must match the preset snapshot
fresh_root key
{ control; row ts typescript:S9999 "code smell" covered sonarjs/cognitive-complexity ""; } > "$T/key.tsv"
run "$T/key.tsv"
check 1 "$EC" "wrong Sonar key for a sonarjs rule fails"
has "row says S9999" "$OUT" "key mismatch message"

# --- usage
OUT=$(env -u CI bash "$CHECK" --bogus 2>&1)
check 2 "$?" "bad flag exits 2"

echo "check-sonar-parity.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

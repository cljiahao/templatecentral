#!/usr/bin/env bash
# scripts/check-sonar-parity.test.sh — tests for scripts/check-sonar-parity.sh on a scratch copy of the configs it reads.
# Usage: bash scripts/check-sonar-parity.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-sonar-parity.sh"
SC="skills/scaffold"
NEXT="$SC/nextjs/template/eslint.config.mjs"
PYP="$SC/fastapi/template/pyproject.toml"
ROW_KEYS_TS="S3776 S4144 S2201 S4822 S9998 CTRL1 CTRL2 CTRL3 CTRL4 CTRL5 CTRL6 CTRLTS CTRLRTC CTRLU CTRLV"
ROW_KEYS_PY="S3776 S1481 S2068 S100 CTRLP2 CTRLP3 CTRLP4 CTRLP5"

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

# fresh_root <name>: a scratch root holding the presets, versions.txt, the four configs and the gate files the control table
# reads. Its sonar-rules snapshot is the real one plus the control keys, so control rows can carry the title "name".
fresh_root() {
  R="$T/$1"
  rm -rf "$R"
  mkdir -p "$R/scripts"
  cp -R "$REPO_ROOT/scripts/sonar-parity-presets" "$R/scripts/"
  local f k
  for f in nextjs/template/eslint.config.mjs vite-react/template/eslint.config.mjs nestjs/template/eslint.config.mjs \
    fastapi/template/pyproject.toml shared/template-ts/.jscpd.json shared/template-py/.jscpd.json \
    shared/template/scripts/gate-ratchet.sh shared/versions.txt; do
    mkdir -p "$R/$SC/$(dirname "$f")"
    cp "$REPO_ROOT/$SC/$f" "$R/$SC/$f"
  done
  for k in $ROW_KEYS_TS; do printf 'ts\t%s\tcode smell\t1\tname\n' "$k" >> "$R/scripts/sonar-parity-presets/sonar-rules.tsv"; done
  for k in $ROW_KEYS_PY; do printf 'py\t%s\tcode smell\t1\tname\n' "$k" >> "$R/scripts/sonar-parity-presets/sonar-rules.tsv"; done
}

# edit <file-under-root> <python expression over the text s>: rewrite a scratch file.
edit() {
  python3 -I -c '
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = eval(expr)
open(p, "w", encoding="utf-8").write(s)
' "$R/$1" "$2"
}

# inject <stack> <js>: add a config block before the end of the scratch eslint config (array or tseslint.config call).
inject() {
  edit "$SC/$1/template/eslint.config.mjs" "s[:s.rstrip().rfind('\n]' if '\n];' in s else '\n)')] + '\n' + '''$2''' + s[s.rstrip().rfind('\n]' if '\n];' in s else '\n)'):]"
}

# prepend <stack> <js>: add a line at the top of the scratch eslint config.
prepend() {
  edit "$SC/$1/template/eslint.config.mjs" "'''$2''' + '\n' + s"
}

# control table: every row passes against the real configs.
control() {
  row ts typescript:S3776 "code smell" covered sonarjs/cognitive-complexity ""
  row ts typescript:CTRL1 "code smell" covered no-warning-comments ""
  row ts typescript:CTRL2 "code smell" not-covered - "needs type information"
  row ts typescript:S4144 "code smell" covered sonarjs/no-identical-functions ""
  row ts typescript:CTRLTS "code smell" covered @typescript-eslint/no-namespace ""
  row ts quality-gate:dup "quality gate" partial 'gate:template-ts/.jscpd.json#"threshold": 3' "whole source, not new code only"
  row ts quality-gate:script "quality gate" covered gate:template/scripts/gate-ratchet.sh ""
  row py python:S3776 "code smell" partial C901 "cyclomatic, not cognitive"
  row py python:S1481 "code smell" covered F841 ""
  row py python:S2068 "code smell" partial S105,S106 "name based"
  row py python:S100 "code smell" not-covered - "pep8-naming is not selected"
  row py python:CTRLP2 "code smell" partial PLR0913 "not compared"
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
has "ts: covered 5, partial 1, not-covered 1" "$OUT" "control summary ts"
has "py: covered 1, partial 3, not-covered 1" "$OUT" "control summary py"
has "not-covered typescript:CTRL2: needs type information" "$OUT" "not-covered rows are listed with reasons"
has "type-aware stacks: nestjs" "$OUT" "type-aware stacks are reported"

# --- preset-only rules: the control rows above read sonarjs and typescript-eslint rules the seeded configs never name,
# so emptying a snapshot must break them
fresh_root nopreset_sonarjs
sed -n '/^#/p' "$REPO_ROOT/scripts/sonar-parity-presets/sonarjs-recommended.tsv" > "$R/scripts/sonar-parity-presets/sonarjs-recommended.tsv"
run "$T/control.tsv"
check 1 "$EC" "empty sonarjs preset breaks the preset-only control row"
has "sonarjs/no-identical-functions is not set in nextjs" "$OUT" "sonarjs preset-only rule is read from the snapshot"

fresh_root nopreset_tse
sed -n '/^#/p' "$REPO_ROOT/scripts/sonar-parity-presets/typescript-eslint-recommended.tsv" > "$R/scripts/sonar-parity-presets/typescript-eslint-recommended.tsv"
run "$T/control.tsv"
check 1 "$EC" "empty typescript-eslint preset breaks the preset-only control row"
has "@typescript-eslint/no-namespace is not set in" "$OUT" "typescript-eslint preset-only rule is read from the snapshot"

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
edit "$SC/vite-react/template/eslint.config.mjs" "''.join(l for l in s.splitlines(True) if 'no-warning-comments' not in l)"
run "$T/control.tsv"
check 1 "$EC" "rule missing from one stack fails"
has "typescript:CTRL1" "$OUT" "absent rule names the row"
has "not set in vite-react" "$OUT" "absent rule names the stack"

# --- a rule set to warn instead of error
fresh_root warn
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace(\"'no-warning-comments': ['error'\", \"'no-warning-comments': ['warn'\")"
run "$T/control.tsv"
check 1 "$EC" "rule at warn fails"
has "is warn in nestjs" "$OUT" "warn names the stack"

# --- a preset rule turned off by the config
fresh_root off
edit "$NEXT" "s.replace(\"'sonarjs/cognitive-complexity': ['error', 15]\", \"'sonarjs/cognitive-complexity': 'off'\")"
run "$T/control.tsv"
check 1 "$EC" "preset rule turned off fails"
has "is off in nextjs" "$OUT" "off names the stack"

# --- a config form the reader cannot resolve fails the row that needs it
fresh_root unresolved
edit "$NEXT" "s.replace(\"'no-warning-comments': ['error'\", \"'no-warning-comments': [level\")"
run "$T/control.tsv"
check 1 "$EC" "unresolvable config fails closed"
has "cannot resolve nextjs eslint config statically" "$OUT" "unresolved message names the stack"
has "typescript:" "$OUT" "unresolved message names a row"

# --- tokenizer: one clear message naming file and line for literals the reader does not support
fresh_root template_literal
prepend nextjs "const note = \`not read\`;"
run "$T/control.tsv"
check 1 "$EC" "template literal in the config fails closed"
has "nextjs/template/eslint.config.mjs:1: unsupported template literal" "$OUT" "tokenizer names file and line"

# --- file scoping: a block that is not provably about every source file or only test files must not pass quietly
fresh_root scope_control
inject nextjs "  { files: ['**/*.test.ts'], rules: { 'no-warning-comments': 'off' } },"
run "$T/control.tsv"
check 0 "$EC" "a rule turned off for test files only still counts as error"
has "no-warning-comments set to off for test files only" "$OUT" "test-only block is reported as a note"

fresh_root scope_all
inject nextjs "  { files: ['**/*.{ts,tsx}'], rules: { 'no-warning-comments': 'error' } },"
run "$T/control.tsv"
check 0 "$EC" "a block over all source extensions is understood"

fresh_root scope_test_on_after_off
inject nextjs "  { rules: { 'no-warning-comments': 'off' } },
  { files: ['**/*.test.ts'], rules: { 'no-warning-comments': 'error' } },"
run "$T/control.tsv"
check 1 "$EC" "a test-glob block turning the rule on after it was turned off does not hide the off"
has "is off in nextjs" "$OUT" "source files stay off"

fresh_root scope_ignores
inject nextjs "  { rules: { 'no-warning-comments': 'off' } },
  { ignores: ['src/**'], rules: { 'no-warning-comments': 'error' } },"
run "$T/control.tsv"
check 1 "$EC" "a block that ignores source folders fails closed"
has "cannot resolve nextjs eslint config statically" "$OUT" "ignores block is unresolved"

fresh_root scope_partial_files
inject nextjs "  { files: ['src/**/*.{ts,tsx}', 'app/**'], rules: { 'no-warning-comments': 'off' } },"
run "$T/control.tsv"
check 1 "$EC" "a block over only some source folders fails closed"
has "cannot prove it covers all source files or only tests" "$OUT" "files glob is unresolved"

fresh_root global_ignores_source
inject nextjs "  { ignores: ['src/**'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of source folders fails closed"
has "global ignores entry 'src/**' is not a build or tooling path" "$OUT" "global ignore message"

fresh_root global_ignores_tooling
inject nextjs "  { ignores: ['dist/**', '*.config.mjs'] },"
run "$T/control.tsv"
check 0 "$EC" "a global ignore of build and tooling paths is fine"

# --- unresolvable forms: a spread, reference or call that is not a known preset or constant
fresh_root unknown_rules_spread
inject nextjs "  { rules: { ...someObj } },"
run "$T/control.tsv"
check 1 "$EC" "spread of an unknown object in rules fails closed"
has "someObj, which is not a known config preset" "$OUT" "rules spread names the reference"

fresh_root unknown_call
inject nextjs "  someHelper({ rules: { 'no-warning-comments': 'off' } }),"
run "$T/control.tsv"
check 1 "$EC" "a helper call as a config element fails closed"
has "call to someHelper in the config is not read" "$OUT" "call message names the helper"

fresh_root unknown_array_spread
inject nextjs "  ...unknownThing,"
run "$T/control.tsv"
check 1 "$EC" "a spread of an unknown value in the config array fails closed"
has "unknownThing, which is not a known config preset" "$OUT" "array spread names the reference"

fresh_root known_const_spread
prepend nextjs "const extra = { 'no-debugger': 'error' };"
inject nextjs "  { rules: { ...extra } },"
run "$T/control.tsv"
check 0 "$EC" "a spread of a constant object literal is resolved"

fresh_root unread_plugin_rule
inject nextjs "  { rules: { 'react-hooks/rules-of-hooks': 'off' } },"
run "$T/control.tsv"
check 0 "$EC" "a rule outside the mapped set does not disturb the check"

# --- type information: a rule that needs it cannot be covered where a stack lints without it
fresh_root rtc_sonarjs
{ control; row ts typescript:S2201 "code smell" covered sonarjs/no-ignored-return ""; } > "$T/rtc1.tsv"
run "$T/rtc1.tsv"
check 1 "$EC" "a type-aware sonarjs rule marked covered fails"
has "sonarjs/no-ignored-return needs type information but nextjs, vite-react lint without it" "$OUT" "sonarjs rtc message"
{ control; row ts typescript:S2201 "code smell" partial sonarjs/no-ignored-return "needs type information"; } > "$T/rtc2.tsv"
run "$T/rtc2.tsv"
check 0 "$EC" "the same rule marked partial passes"

fresh_root rtc_tse
{ control; row ts typescript:CTRLRTC "code smell" covered @typescript-eslint/no-floating-promises ""; } > "$T/rtc3.tsv"
run "$T/rtc3.tsv"
check 1 "$EC" "a type-aware typescript-eslint rule marked covered fails"
has "@typescript-eslint/no-floating-promises needs type information" "$OUT" "typescript-eslint rtc message"
{ control; row ts typescript:CTRLRTC "code smell" partial @typescript-eslint/no-floating-promises "needs type information"; } > "$T/rtc4.tsv"
run "$T/rtc4.tsv"
check 0 "$EC" "the same typescript-eslint rule marked partial passes"

fresh_root rtc_typed_nestjs_off
edit "$SC/nestjs/template/eslint.config.mjs" "s.rstrip()[:-2] + \"  { rules: { '@typescript-eslint/no-floating-promises': 'off' } },\n);\n\""
run "$T/rtc4.tsv"
check 1 "$EC" "a partial type-aware row still needs the rule on where types are available"
has "is off in nestjs" "$OUT" "type-aware stack must enable the rule"

# --- Sonar metadata: type and title come from the sonar-rules snapshot; a key it lacks must say unverified
fresh_root meta_name
{ control; row ts typescript:S1481 "code smell" covered sonarjs/no-unused-vars ""; } > "$T/meta1.tsv"
run "$T/meta1.tsv"
check 1 "$EC" "a title that differs from the Sonar metadata fails"
has "name differs from the Sonar metadata title" "$OUT" "title mismatch message"

fresh_root meta_type
{ control; printf 'ts\ttypescript:S1481\tUnused local variables and functions should be removed\tbug\tcovered\tsonarjs/no-unused-vars\t\n'; } > "$T/meta2.tsv"
run "$T/meta2.tsv"
check 1 "$EC" "a type that differs from the Sonar metadata fails"
has "is 'code smell' in the Sonar metadata" "$OUT" "type mismatch message"

fresh_root meta_unknown
{ control; row ts typescript:S0001 "code smell" not-covered - "no local rule"; } > "$T/meta3.tsv"
run "$T/meta3.tsv"
check 1 "$EC" "a key missing from the metadata snapshot without an unverified marker fails"
has "key is not in the sonar-rules snapshot" "$OUT" "unknown key message"
{ control; row ts typescript:S0001 "code smell" not-covered - "unverified: not in the public metadata"; } > "$T/meta4.tsv"
run "$T/meta4.tsv"
check 0 "$EC" "the same key with an unverified marker passes"
has "unverified rows: 1" "$OUT" "unverified rows are counted"

# --- ruff: code removed from select, and code added to ignore
fresh_root ruff
edit "$PYP" "s.replace('\"C901\", ', '')"
run "$T/control.tsv"
check 1 "$EC" "ruff code missing from select fails"
has "ruff C901 is not enabled" "$OUT" "ruff message names the code"

fresh_root ruffignore
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nignore = [\"F841\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "ruff code in ignore fails"
has "ruff F841 is not enabled" "$OUT" "ignored code is named"

fresh_root ruffspecific_ignore
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nignore = [\"F84\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "an ignore more specific than the select entry wins"
has "ruff F841 is not enabled" "$OUT" "specific ignore names the code"

fresh_root ruffspecific_select
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nignore = [\"PLR\"]\n', 1)"
run "$T/control.tsv"
check 0 "$EC" "a select entry more specific than the ignore wins"

fresh_root ruff_pfi
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\"app/**/*.py\" = [\"C901\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a per-file-ignores entry outside test paths that disables a mapped code fails"
has "per-file-ignores 'app/**/*.py' disables ruff C901 outside test paths" "$OUT" "per-file-ignores message"

fresh_root ruff_pfi_test
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\"test/**/*.py\" = [\"C901\"]\n', 1)"
run "$T/control.tsv"
check 0 "$EC" "a per-file-ignores entry for test paths only is fine"

fresh_root ruff_extend_pfi
edit "$PYP" "s + '\n[tool.ruff.lint.extend-per-file-ignores]\n\"app/**/*.py\" = [\"F841\"]\n'"
run "$T/control.tsv"
check 1 "$EC" "an extend-per-file-ignores entry outside test paths fails"
has "per-file-ignores 'app/**/*.py' disables ruff F841 outside test paths" "$OUT" "extend-per-file-ignores is read"

fresh_root ruff_preview
{ control; row py python:CTRLP3 "code smell" partial S405 "preview-only"; } > "$T/preview.tsv"
run "$T/preview.tsv"
check 1 "$EC" "a preview-only code without preview enabled fails"
has "ruff S405 is not enabled in fastapi (preview-only rule and preview is not enabled)" "$OUT" "preview message"
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\npreview = true\n', 1)"
run "$T/preview.tsv"
check 0 "$EC" "the same code passes once preview is enabled"

fresh_root ruff_unknown_code
{ control; row py python:CTRLP4 "code smell" partial ZZ999 "no such code"; } > "$T/zz.tsv"
run "$T/zz.tsv"
check 1 "$EC" "a code absent from the ruff snapshot fails"
has "ruff code ZZ999 is not in the ruff-rules snapshot" "$OUT" "unknown ruff code message"

fresh_root ruff_inline_pfi
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nper-file-ignores = {\"app/*.py\" = [\"C901\"]}\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "inline per-file-ignores fails closed"
has "inline per-file-ignores is not read" "$OUT" "inline form message"

# --- preset pins: a snapshot must match the pin in versions.txt
fresh_root pin_mismatch
edit "$SC/shared/versions.txt" "s.replace('eslint-plugin-sonarjs         4.2.2', 'eslint-plugin-sonarjs         4.2.3')"
run "$T/control.tsv"
check 1 "$EC" "a snapshot for another version than versions.txt pins fails"
has "snapshot sonarjs-recommended was generated for npm eslint-plugin-sonarjs 4.2.2 but versions.txt pins 4.2.3; regenerate it" "$OUT" "pin mismatch message"

fresh_root pin_missing
edit "scripts/sonar-parity-presets/eslint-recommended.tsv" "''.join(l for l in s.splitlines(True) if not l.startswith('# pin:'))"
run "$T/control.tsv"
check 1 "$EC" "a snapshot without a pin line fails"
has "snapshot eslint-recommended has no '# pin:' line" "$OUT" "missing pin message"

# --- off entries the typescript-eslint presets keep for base rules
fresh_root base_off
{ control; row ts typescript:CTRLU "code smell" covered no-unused-vars ""; } > "$T/baseoff.tsv"
run "$T/baseoff.tsv"
check 1 "$EC" "a base rule the typescript-eslint preset turns off is not counted as on"
has "no-unused-vars is off in" "$OUT" "base rule is off from the preset"

# --- gate script missing
fresh_root gate
rm "$R/$SC/shared/template/scripts/gate-ratchet.sh"
run "$T/control.tsv"
check 1 "$EC" "missing gate script fails"
has "gate file missing: template/scripts/gate-ratchet.sh" "$OUT" "missing gate message"

fresh_root gateneedle
edit "$SC/shared/template-ts/.jscpd.json" "s.replace('\"threshold\": 3', '\"threshold\": 9')"
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

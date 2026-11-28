#!/usr/bin/env bash
# scripts/check-sonar-parity.test.sh — tests for scripts/check-sonar-parity.sh on a scratch copy of the configs it reads.
# Usage: bash scripts/check-sonar-parity.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-sonar-parity.sh"
SC="skills/scaffold"
NEXT="$SC/nextjs/template/eslint.config.mjs"
PYP="$SC/fastapi/template/pyproject.toml"
ROW_KEYS_TS="S3776 S4144 S2201 S4822 S9998 CTRL1 CTRL2 CTRL3 CTRL4 CTRL5 CTRL6 CTRLTS CTRLRTC CTRLU CTRLV CTRLIMP"
ROW_KEYS_PY="S3776 S1481 S2068 S100 CTRLP2 CTRLP3 CTRLP4 CTRLP5"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

lacks() { # lacks <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] unexpectedly in [$2]"; fi
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

fresh_root global_ignores_helper
inject nextjs "  { ignores: ['scripts/check-comments.mjs'] },"
run "$T/control.tsv"
check 0 "$EC" "a global ignore of an exact seeded gate helper is fine"

fresh_root global_ignores_helper_group
inject nextjs "  { ignores: ['scripts/{check-comments,duplicate-tests-ts}.mjs'] },"
run "$T/control.tsv"
check 0 "$EC" "a brace group of exact seeded gate helpers is fine"

fresh_root global_ignores_helper_group_extra
inject nextjs "  { ignores: ['scripts/{check-comments,my-own}.mjs'] },"
run "$T/control.tsv"
check 1 "$EC" "a brace group naming a file that is not a seeded helper fails closed"
has "is not a build or tooling path" "$OUT" "brace group message"

fresh_root global_ignores_scripts_glob
inject nextjs "  { ignores: ['scripts/**'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of the whole scripts folder fails closed"
has "global ignores entry 'scripts/**' is not a build or tooling path" "$OUT" "scripts glob message"

fresh_root global_ignores_helper_lookalike
inject nextjs "  { ignores: ['scripts/check-comments.mjs.bak', 'scripts/other.mjs'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of a name next to a seeded helper fails closed"

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

fresh_root layers_import_known
run "$T/rtc4.tsv"
check 0 "$EC" "control: the seeded layers.config.mjs import resolves ($OUT)"
fresh_root layers_import_other
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace(\"'./layers.config.mjs'\", \"'./other.mjs'\")"
run "$T/rtc4.tsv"
check 1 "$EC" "a layer config imported from any other file is not read"
has "not a known config preset" "$OUT" "the unknown import is named as unknown"

{ control; row ts typescript:CTRLIMP "code smell" covered no-restricted-imports ""; } > "$T/imp.tsv"
fresh_root layers_row
run "$T/imp.tsv"
check 1 "$EC" "a row mapped to no-restricted-imports fails because the layers config is not read rule by rule"
has "config reference that is not read rule by rule" "$OUT" "the layers reference message"
for st in nestjs nextjs vite-react; do
  has "$st" "$OUT" "the layers row fails on $st"
done
fresh_root layers_row_off
for st in nestjs nextjs vite-react; do
  inject "$st" "  { rules: { 'no-restricted-imports': 'off' } },"
done
run "$T/imp.tsv"
check 1 "$EC" "a later rule-off entry does not make a no-restricted-imports row pass"
has "config reference that is not read rule by rule" "$OUT" "the layers reference message with a later rule-off entry"

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
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\"test/unit/**/*.py\" = [\"C901\"]\n', 1)"
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
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nper-file-ignores = {\"app/*.py\" = [\"C901\"]}\n', 1).replace('[tool.ruff.lint.per-file-ignores]', '[tool.ruff.lint.other]')"
run "$T/control.tsv"
check 1 "$EC" "inline per-file-ignores fails closed"
has "inline per-file-ignores is not read" "$OUT" "inline form message"

# --- object-literal order: a 'rules' key replaces the rules of an earlier block-level spread, a later spread replaces it back
fresh_root obj_rules_replace
edit "$NEXT" "s.replace('      ...sonarjs.configs.recommended.rules,\n', '', 1)"
run "$T/control.tsv"
check 1 "$EC" "a rules key without the preset's rules spread drops the preset rules"
has "sonarjs/no-identical-functions is not set in nextjs" "$OUT" "preset-only rule is gone after the rules key replaced it"

fresh_root obj_rules_spread_after
inject nextjs "  { rules: { 'no-warning-comments': 'off' }, ...sonarjs.configs.recommended },"
run "$T/control.tsv"
check 0 "$EC" "a later spread replaces an earlier rules key, so the block no longer turns the rule off"

# --- type information: parserOptions is read as an object and must cover all source files
fresh_root ta_false
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('projectService: true,', 'projectService: false,')"
run "$T/control.tsv"
has "type-aware stacks: none" "$OUT" "projectService false is not type-aware"

fresh_root ta_test_only
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('    languageOptions: {', \"    files: ['**/*.test.ts'],\n    languageOptions: {\", 1)"
run "$T/control.tsv"
has "type-aware stacks: none" "$OUT" "projectService in a test-only block is not type-aware"

fresh_root ta_settings_project
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('projectService: true,', 'projectService: false,')"
inject nestjs "  { settings: { project: 'x' } },"
run "$T/control.tsv"
has "type-aware stacks: none" "$OUT" "a project key under settings is not type-aware"

fresh_root ta_project_empty
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('projectService: true,', \"project: '',\")"
run "$T/control.tsv"
has "type-aware stacks: none" "$OUT" "an empty project string is not type-aware"

fresh_root ta_project_set
inject vite-react "  { languageOptions: { parserOptions: { project: ['./tsconfig.json'] } } },"
run "$T/control.tsv"
has "type-aware stacks: vite-react, nestjs" "$OUT" "a project array over all files is type-aware"

fresh_root ta_spread
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('projectService: true,', '...opts,')"
run "$T/control.tsv"
check 1 "$EC" "a spread inside parserOptions fails closed"
has "a spread in parserOptions is not read" "$OUT" "parserOptions spread message"

# --- ruff selectors: the longest linter prefix picks the linter, so 'S' is bandit only and never SIM
fresh_root ruff_sel_sim
edit "$PYP" "s.replace('\"SIM\", ', '')"
{ control; row py python:CTRLP3 "code smell" covered SIM102 ""; } > "$T/sim.tsv"
run "$T/sim.tsv"
check 1 "$EC" "dropping SIM from select fails although S is still selected"
has "ruff SIM102 is not enabled in fastapi (not selected)" "$OUT" "S does not select SIM"

fresh_root ruff_sel_era
edit "$PYP" "s.replace('\"ERA\", ', '\"E\", ')"
{ control; row py python:CTRLP4 "code smell" covered ERA001 ""; } > "$T/era.tsv"
run "$T/era.tsv"
check 1 "$EC" "E in select does not enable ERA001"
has "ruff ERA001 is not enabled in fastapi (not selected)" "$OUT" "E does not select ERA"

fresh_root ruff_sel_arg
edit "$PYP" "s.replace('\"ARG\"', '\"A\"')"
{ control; row py python:CTRLP5 "code smell" covered ARG001 ""; } > "$T/arg.tsv"
run "$T/arg.tsv"
check 1 "$EC" "A in select does not enable ARG001"
has "ruff ARG001 is not enabled in fastapi (not selected)" "$OUT" "A does not select ARG"

fresh_root ruff_sel_group
edit "$PYP" "s.replace('\"PLR0913\"', '\"PL\"')"
run "$T/control.tsv"
check 0 "$EC" "PL selects the whole Pylint group"

fresh_root ruff_sel_unknown
edit "$PYP" "s.replace('\"ERA\", ', '\"ERA\", \"ZZ\", ')"
run "$T/control.tsv"
check 1 "$EC" "a selector that names no linter fails closed"
has "ruff selector 'ZZ' is not a code or linter prefix" "$OUT" "unknown selector message"

fresh_root ruff_pfi_bandit
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\"app/**\" = [\"S\"]\n', 1)"
{ control; row py python:CTRLP3 "code smell" covered SIM102 ""; } > "$T/sim.tsv"
run "$T/sim.tsv"
check 1 "$EC" "a per-file-ignores entry for S outside tests fails"
has "per-file-ignores 'app/**' disables ruff S105 outside test paths" "$OUT" "S ignore blames the bandit row"
lacks "disables ruff SIM102" "$OUT" "S ignore does not blame SIM rows"

# --- round 3: pyproject.toml is read by one strict scanner
fresh_root lit_ignore
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nignore = [\'SIM\']\n', 1)"
{ control; row py python:CTRLP3 "code smell" covered SIM102 ""; } > "$T/sim.tsv"
run "$T/sim.tsv"
check 1 "$EC" "a literal-string ignore entry is read"
has "ruff SIM102 is not enabled" "$OUT" "literal ignore names the code"

fresh_root lit_select
edit "$PYP" "s.replace('\"SIM\", ', '\'SIM\', ')"
run "$T/sim.tsv"
check 0 "$EC" "a literal-string select entry is read"

fresh_root lit_pfi
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\'app/**\' = [\'S\']\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a literal-string per-file-ignores key and value are read"
has "per-file-ignores 'app/**' disables ruff S105 outside test paths" "$OUT" "literal pfi message"

fresh_root lit_pfi_test
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\'test/**\' = [\'S\']\n', 1)"
run "$T/control.tsv"
check 0 "$EC" "a literal-string per-file-ignores entry for tests passes"

fresh_root cmt_bracket
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nignore = [\"E\", # see [x]\n  \"F841\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a bracket inside a comment does not truncate the list"
has "ruff F841 is not enabled" "$OUT" "entry after a commented bracket is read"

fresh_root cmt_bracket_ok
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nignore = [\"E\", # see [x]\n  \"E501\"]\n', 1)"
run "$T/control.tsv"
check 0 "$EC" "the same list without F841 passes"

fresh_root cmt_bracket_pfi
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\"app/**/*.py\" = [\"E\", # see [x]\n  \"C901\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a bracket inside a comment does not truncate a per-file-ignores list"
has "per-file-ignores 'app/**/*.py' disables ruff C901 outside test paths" "$OUT" "pfi entry after a commented bracket is read"

fresh_root hash_in_string
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nignore = [\"F8#41\", \"F841\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a hash inside a string is not a comment"

fresh_root prev_override
{ control; row py python:CTRLP3 "code smell" partial S405 "preview-only"; } > "$T/preview.tsv"
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\npreview = true\n', 1).replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\npreview = false\n', 1)"
run "$T/preview.tsv"
check 1 "$EC" "lint.preview = false overrides top-level preview = true"
has "ruff S405 is not enabled in fastapi (preview-only rule and preview is not enabled)" "$OUT" "override message"

fresh_root prev_top_only
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\npreview = true\n', 1)"
run "$T/preview.tsv"
check 0 "$EC" "top-level preview = true alone enables preview"

fresh_root prev_lint_over_top
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\npreview = false\n', 1).replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\npreview = true\n', 1)"
run "$T/preview.tsv"
check 0 "$EC" "lint.preview = true overrides top-level preview = false"

fresh_root prev_nonbool
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\npreview = \"yes\"\n', 1)"
run "$T/preview.tsv"
check 1 "$EC" "a non-boolean preview fails closed"
has "preview is not a boolean literal" "$OUT" "preview literal message"

fresh_root toml_dupkey
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nline-length = 99\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a duplicate key fails closed"
has "duplicate key line-length" "$OUT" "duplicate key message"

fresh_root toml_multiline
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nextend = \"\"\"x\"\"\"\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a multi-line string under [tool.ruff] fails closed"
has "multi-line strings are not read" "$OUT" "multi-line message"

fresh_root toml_escape
edit "$PYP" "s.replace('target-version = \"py314\"', 'target-version = \"py3\\\\q\"', 1)"
run "$T/control.tsv"
check 1 "$EC" "an undecoded escape under [tool.ruff] fails closed"
has "is not decoded" "$OUT" "escape message"

fresh_root toml_inline_lint
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nlint = { select = [\"F\"] }\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "an inline lint table followed by a lint header fails closed"
has "table [tool.ruff.lint] is defined twice" "$OUT" "inline lint message"

fresh_root toml_dotted_ok
edit "$PYP" "s + '\n[tool.ruff.lint.isort]\nsplit.deep = [\"a\"]\nknown-first-party = [\"app\"]\n'"
run "$T/control.tsv"
check 0 "$EC" "dotted keys and arrays in an unrelated table parse"

# --- round 3: only root-anchored tooling folders count as tooling
fresh_root tool_dist_any
inject nextjs "  { ignores: ['**/dist/**'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of dist at any depth fails closed"
has "global ignores entry '**/dist/**' is not a build or tooling path" "$OUT" "any-depth dist message"

fresh_root tool_build_any
inject nextjs "  { ignores: ['**/build/**'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of build at any depth fails closed"

fresh_root tool_out_any
inject nextjs "  { ignores: ['**/out/**'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of out at any depth fails closed"

fresh_root tool_src_out
inject nextjs "  { ignores: ['src/out/**'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of out under src fails closed"

fresh_root tool_dist_root
inject nextjs "  { ignores: ['dist/**'] },"
run "$T/control.tsv"
check 0 "$EC" "a global ignore of root dist passes"

fresh_root tool_node_modules_any
inject nextjs "  { ignores: ['**/node_modules/**'] },"
run "$T/control.tsv"
check 0 "$EC" "a global ignore of node_modules at any depth passes"

# --- round 3: ruff selectors accept exact linters and the PL group only
fresh_root sel_pg
edit "$PYP" "s.replace('\"ERA\", ', '\"ERA\", \"PG\", ')"
run "$T/control.tsv"
check 1 "$EC" "PG is a prefix of PGH but not a selector"
has "ruff selector 'PG' is not a code or linter prefix" "$OUT" "PG message"

fresh_root sel_r
edit "$PYP" "s.replace('\"ERA\", ', '\"ERA\", \"R\", ')"
run "$T/control.tsv"
check 1 "$EC" "R is a prefix of RET and RUF but not a selector"
has "ruff selector 'R' is not a code or linter prefix" "$OUT" "R message"

# --- round 3: duplicate keys follow last-wins
fresh_root ta_dup_service
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('projectService: true,', 'projectService: true,\n        projectService: false,')"
run "$T/control.tsv"
has "type-aware stacks: none" "$OUT" "a later projectService: false wins"

fresh_root ta_dup_service_ok
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('projectService: true,', 'projectService: false,\n        projectService: true,')"
run "$T/control.tsv"
has "type-aware stacks: nestjs" "$OUT" "a later projectService: true wins"

fresh_root ta_dup_opts
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('        tsconfigRootDir: import.meta.dirname,\n      },\n', '        tsconfigRootDir: import.meta.dirname,\n      },\n      parserOptions: { tsconfigRootDir: \'x\' },\n', 1)"
run "$T/control.tsv"
has "type-aware stacks: none" "$OUT" "a later parserOptions replaces the earlier object"

fresh_root ta_dup_opts_ok
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('      sourceType: \'module\',\n', '      sourceType: \'module\',\n      parserOptions: { tsconfigRootDir: \'x\' },\n', 1)"
run "$T/control.tsv"
has "type-aware stacks: nestjs" "$OUT" "an earlier parserOptions is replaced by the later one"

# --- round 3: a spread in languageOptions is one problem naming the block
fresh_root ta_lo_spread
edit "$SC/nestjs/template/eslint.config.mjs" "s.replace('      sourceType: \'module\',\n', '      ...lo,\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a spread inside languageOptions fails closed"
has "a spread in languageOptions is not read, in the block with keys languageOptions" "$OUT" "languageOptions spread names the block"
N=$(printf '%s\n' "$OUT" | grep -c "cannot resolve nestjs eslint config")
check 1 "$N" "the unresolved stack is reported once, not per row"

# --- ruff forms ruff reads that this check does not: each must raise
fresh_root ruff_dotted_top
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nlint.ignore = [\"F841\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a dotted lint.* key under [tool.ruff] fails closed"
has "table [tool.ruff.lint] is defined twice" "$OUT" "dotted top key message"

fresh_root ruff_dotted_lint
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nper-file-ignores.\"app/*.py\" = [\"C901\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a dotted key under [tool.ruff.lint] fails closed"
has "table [tool.ruff.lint.per-file-ignores] is defined twice" "$OUT" "dotted lint key message"

fresh_root ruff_extend
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nextend = \"../base.toml\"\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "ruff extend fails closed"
has "extend in [tool.ruff] pulls in a config that is not read" "$OUT" "extend message"

fresh_root ruff_toml_beside
: > "$R/$SC/fastapi/template/ruff.toml"
run "$T/control.tsv"
check 1 "$EC" "a ruff.toml beside pyproject.toml fails closed"
has "ruff.toml beside pyproject.toml takes precedence" "$OUT" "ruff.toml message"

fresh_root dot_ruff_toml_beside
: > "$R/$SC/fastapi/template/.ruff.toml"
run "$T/control.tsv"
check 1 "$EC" "a .ruff.toml beside pyproject.toml fails closed"
has ".ruff.toml beside pyproject.toml takes precedence" "$OUT" ".ruff.toml message"

fresh_root ruff_explicit_preview
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\npreview = true\nexplicit-preview-rules = true\n', 1)"
{ control; row py python:CTRLP3 "code smell" partial S405 "preview-only"; } > "$T/preview.tsv"
run "$T/preview.tsv"
check 1 "$EC" "explicit-preview-rules: a bare S does not enable preview rule S405"
has "explicit-preview-rules needs its exact code in select" "$OUT" "explicit preview message"
edit "$PYP" "s.replace('\"S\", ', '\"S\", \"S405\", ', 1)"
run "$T/preview.tsv"
check 0 "$EC" "explicit-preview-rules: the exact code enables it"

# --- legacy and unread ruff settings raise
fresh_root ruff_legacy_select
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nselect = [\"E\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a legacy top-level select fails closed"
has "legacy top-level select in [tool.ruff]" "$OUT" "legacy select message"

fresh_root ruff_legacy_ignore
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nignore = [\"F841\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a legacy top-level ignore fails closed"
has "legacy top-level ignore in [tool.ruff]" "$OUT" "legacy ignore message"

fresh_root ruff_exclude
edit "$PYP" "s.replace('line-length = 88\n', 'line-length = 88\nexclude = [\"app\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "ruff exclude fails closed"
has "exclude is not read" "$OUT" "exclude message"

fresh_root ruff_extend_exclude
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nextend-exclude = [\"app\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "ruff extend-exclude under lint fails closed"
has "extend-exclude is not read" "$OUT" "extend-exclude message"

fresh_root ruff_extend_exclude_top_source
edit "$PYP" "s.replace('extend-exclude = [', 'extend-exclude = [\"src\",', 1)"
run "$T/control.tsv"
check 1 "$EC" "a top-level extend-exclude that hides a source folder fails closed"
has "extend-exclude is not read" "$OUT" "top-level extend-exclude message"

fresh_root ruff_extend_exclude_seeded_helpers
run "$T/control.tsv"
check 0 "$EC" "a top-level extend-exclude of only the seeded Python helpers passes"

fresh_root ruff_extend_exclude_empty
edit "$PYP" "s.replace('extend-exclude = [', 'extend-exclude = []\nignored-key = [', 1)"
run "$T/control.tsv"
check 1 "$EC" "an empty top-level extend-exclude fails closed"
has "extend-exclude is not read" "$OUT" "empty extend-exclude message"

fresh_root ruff_extend_exclude_duplicate
edit "$PYP" "s.replace('extend-exclude = [', 'extend-exclude = [\"scripts/py-env.py\", \"scripts/py-env.py\",', 1)"
run "$T/control.tsv"
check 1 "$EC" "a top-level extend-exclude with a duplicate entry fails closed"
has "extend-exclude is not read" "$OUT" "duplicate extend-exclude message"

fresh_root ruff_force_exclude_off
edit "$PYP" "s.replace('force-exclude = true', 'force-exclude = false', 1)"
run "$T/control.tsv"
check 1 "$EC" "extend-exclude with force-exclude = false fails closed"
has "extend-exclude needs force-exclude = true" "$OUT" "force-exclude message"

fresh_root ruff_inline_extend_pfi
edit "$PYP" "s.replace('[tool.ruff.lint]\n', '[tool.ruff.lint]\nextend-per-file-ignores = {\"app/*.py\" = [\"C901\"]}\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "inline extend-per-file-ignores fails closed"
has "inline extend-per-file-ignores is not read" "$OUT" "inline extend form message"

# --- config references that are not read rule by rule
fresh_root touches_prefix
{ control; row ts typescript:CTRLV "code smell" covered react-hooks/rules-of-hooks ""; } > "$T/touch.tsv"
run "$T/touch.tsv"
check 1 "$EC" "a mapped rule under a prefix a config reference touches fails closed"
has "is under react-hooks/, set by a config reference that is not read rule by rule" "$OUT" "touches message"

# --- paths with '..' segments are never test or tooling paths
fresh_root dotdot_ignores
inject nextjs "  { ignores: ['dist/../src/**'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore that climbs out of a tooling folder fails closed"
has "global ignores entry 'dist/../src/**' is not a build or tooling path" "$OUT" "dotdot ignore message"

fresh_root dotdot_files
inject nextjs "  { files: ['test/../src/**/*.ts'], rules: { 'no-warning-comments': 'off' } },"
run "$T/control.tsv"
check 1 "$EC" "a files glob that climbs out of a test folder is not a test block"
has "cannot prove it covers all source files or only tests" "$OUT" "dotdot files message"

fresh_root dotdot_pfi
edit "$PYP" "s.replace('[tool.ruff.lint.per-file-ignores]\n', '[tool.ruff.lint.per-file-ignores]\n\"test/../src/**/*.py\" = [\"C901\"]\n', 1)"
run "$T/control.tsv"
check 1 "$EC" "a per-file-ignores key that climbs out of a test folder is not a test path"
has "per-file-ignores 'test/../src/**/*.py' disables ruff C901 outside test paths" "$OUT" "dotdot pfi message"

# --- config-file ignores count as tooling only at the project root
fresh_root config_any_depth
inject nextjs "  { ignores: ['**/*.config.ts'] },"
run "$T/control.tsv"
check 1 "$EC" "a global ignore of config files at any depth fails closed"
has "global ignores entry '**/*.config.ts' is not a build or tooling path" "$OUT" "any-depth config ignore message"

fresh_root config_root
inject nextjs "  { ignores: ['*.config.ts'] },"
run "$T/control.tsv"
check 0 "$EC" "a global ignore of root config files is fine"

# --- a later block over all source files hides an earlier partial block
fresh_root partial_then_all
inject nextjs "  { files: ['src/**/*.ts'], rules: { 'no-warning-comments': 'off' } },
  { rules: { 'no-warning-comments': 'error' } },"
run "$T/control.tsv"
check 0 "$EC" "a partial off block followed by an all-files block that enables the rule passes"

fresh_root all_then_partial
inject nextjs "  { rules: { 'no-warning-comments': 'error' } },
  { files: ['src/**/*.ts'], rules: { 'no-warning-comments': 'off' } },"
run "$T/control.tsv"
check 1 "$EC" "an all-files block followed by a partial off block still fails closed"
has "cannot prove it covers all source files or only tests" "$OUT" "partial later block is unresolved"

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

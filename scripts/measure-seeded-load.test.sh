#!/usr/bin/env bash
# scripts/measure-seeded-load.test.sh — tests for scripts/measure-seeded-load.sh.
# Usage: bash scripts/measure-seeded-load.test.sh
set -uo pipefail
export TC_TEST=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEASURE="$REPO_ROOT/scripts/measure-seeded-load.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/measure-load-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# fresh_root <name>: a copy of the scaffold tree to plant files in.
fresh_root() {
  mkdir -p "$T/$1/skills"
  cp -Rp "$REPO_ROOT/skills/scaffold" "$T/$1/skills/scaffold"
}

# run <root> [stacks]: exit code and output of the measure script against that root. Planted cases name the one stack they touch and skip the hook fixtures; the first case runs everything.
run() { OUT=$(MEASURE_STACKS="${2:-nextjs}" MEASURE_HOOKS=0 bash "$MEASURE" --root "$1" 2>&1); EC=$?; }


OUT=$(bash "$MEASURE" --root "$REPO_ROOT" 2>&1); EC=$?
check 0 "$EC" "the repository is within budget"
check 4 "$(printf '%s\n' "$OUT" | grep -c '^[a-z-]* *CLAUDE ')" "one table row per stack"

fresh_root big
printf '%s\n' "$(python3 -c 'print("Filler words that bloat the always-loaded file. " * 120)')" >> "$T/big/skills/scaffold/nextjs/template-agents/AGENTS.md"
run "$T/big"
check 1 "$EC" "an over-budget AGENTS.md fails"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'FAIL: nextjs: always-loaded')" "the over-budget stack is named"

fresh_root dup
SENT="Every migration needs a rollback plan written before the first deploy."
printf '\n%s\n' "$SENT" >> "$T/dup/skills/scaffold/vite-react/template-agents/AGENTS.md"
python3 - "$T/dup/skills/scaffold/vite-react/template/.claude/skills/vite-verify/SKILL.md.tmpl" "$SENT" <<'PY'
import re, sys
p, s = sys.argv[1:]
t = open(p).read()
open(p, "w").write(re.sub(r"^description:.*$", lambda m: "description: " + s + " " + m.group(0)[len("description:"):].lstrip(), t, count=1, flags=re.M))
PY
run "$T/dup" vite-react
check 1 "$EC" "a sentence in two always-loaded files fails"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'FAIL: vite-react: sentence in')" "the duplicated sentence is reported"

# plant_rule <root> <relpath> <frontmatter-or-empty>: a ~5 KB rule in the nextjs template, with its manifest row.
plant_rule() {
  local tpl="$1/skills/scaffold/nextjs" f="$1/skills/scaffold/nextjs/template/.claude/rules/$2"
  mkdir -p "$(dirname "$f")"
  { [[ -n "$3" ]] && printf -- '---\n%s\n---\n' "$3"; python3 -c 'print("".join("Rule line number %d says something unique. " % i for i in range(150)))'; } > "$f"
  chmod 644 "$f"
  printf 'template/.claude/rules/%s 644 - -\n' "$2" >> "$tpl/template.manifest"
}

fresh_root nested
plant_rule "$T/nested" deep/big.md ""
run "$T/nested"
check 1 "$EC" "a nested unscoped rule over budget fails"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'FAIL: nextjs: always-loaded')" "the nested rule counts toward the nextjs load"

fresh_root scoped
plant_rule "$T/scoped" deep/big.md 'paths:
  - "src/**/*.ts"'
run "$T/scoped"
check 0 "$EC" "a nested path-scoped rule is not counted"

# plant_doc <root> <name> <content>: a seeded docs/ file in the nextjs template, with its manifest row.
plant_doc() {
  mkdir -p "$1/skills/scaffold/nextjs/template/docs"
  printf '%s\n' "$3" > "$1/skills/scaffold/nextjs/template/docs/$2"
  chmod 644 "$1/skills/scaffold/nextjs/template/docs/$2"
  printf 'template/docs/%s 644 - -\n' "$2" >> "$1/skills/scaffold/nextjs/template.manifest"
}

fresh_root imp
plant_doc "$T/imp" BIG.md "$(python3 -c 'print("Imported words that bloat the context. " * 150)')"
printf '\n@docs/BIG.md\n' >> "$T/imp/skills/scaffold/nextjs/template-agents/AGENTS.md"
run "$T/imp"
check 1 "$EC" "an @import of a large file fails"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'FAIL: nextjs: always-loaded')" "the import counts toward the nextjs load"

fresh_root cycle
plant_doc "$T/cycle" A.md "$(printf 'Small file a.\n@B.md')"
plant_doc "$T/cycle" B.md "$(printf 'Small file b.\n@A.md\n@../AGENTS.md')"
printf '\n@docs/A.md\n' >> "$T/cycle/skills/scaffold/nextjs/template-agents/AGENTS.md"
run "$T/cycle"
check 0 "$EC" "an import cycle ends and passes"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'nextjs .*imports   *[1-9]')" "the cycle's files are counted"

# The failure names the largest contributing files.
fresh_root top
plant_doc "$T/top" BIG.md "$(python3 -c 'print("Imported words that bloat the context. " * 150)')"
printf '\n@docs/BIG.md\n' >> "$T/top/skills/scaffold/nextjs/template-agents/AGENTS.md"
run "$T/top"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'FAIL: nextjs: always-loaded .*largest: .*docs/BIG.md [0-9]')" "an over-budget failure names the largest files"

# A rule with an empty or missing paths list loads at launch and is counted.
for fm in 'paths:' 'paths: []' 'paths: ""' 'paths:
other: x'; do
  fresh_root emptypaths
  plant_rule "$T/emptypaths" deep/big.md "$fm"
  run "$T/emptypaths"
  check 1 "$EC" "a rule with $(printf '%s' "$fm" | head -1 | tr -d '\n') and no patterns counts as always-loaded"
  rm -rf "$T/emptypaths"
done

# Unenforced invariants stay in the always-loaded layer, and the docs say the constitution is read on demand.
SH="$REPO_ROOT/skills/scaffold/shared"
check 1 "$(grep -c 'Authenticate every route that reads or changes user data' "$SH/template-tail/AGENTS-tail.md")" "the tail keeps the authenticate-before-logic line"
check 1 "$(grep -c 'never install one that hardcodes secrets or makes outbound calls' "$SH/template-tail/AGENTS-tail.md")" "the tail keeps the skills-security line"
check 4 "$(grep -l 'every security hotspot reviewed' "$REPO_ROOT"/skills/scaffold/*/template-agents/AGENTS.md | wc -l | tr -d ' ')" "every stack gate line keeps the security-hotspot review"
check 1 "$(grep -c 'is read on demand and is not injected at session start' "$SH/template-late/docs/harness.md")" "harness.md says the constitution is read on demand"
# Pending entries live in changelog.d/ fragments until a release folds them into CHANGELOG.md.
check 1 "$(cat "$REPO_ROOT/CHANGELOG.md" "$REPO_ROOT"/changelog.d/*.md | grep -c 'read on demand and is not injected at session start')" "CHANGELOG or a pending fragment says the constitution is read on demand"

echo "measure-seeded-load.test.sh: $PASS passed, $FAIL failed in ${SECONDS}s"
[[ "$FAIL" -eq 0 ]]

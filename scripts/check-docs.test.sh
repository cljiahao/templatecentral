#!/usr/bin/env bash
# scripts/check-docs.test.sh — tests for the seeded scripts/check-docs.sh.
# Usage: bash scripts/check-docs.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO_ROOT/skills/scaffold/shared"
CHECK="$SHARED/template/scripts/check-docs.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# A backtick for building Markdown spans in double-quoted strings.
BT=$(printf '\140')

T=$(mktemp -d "${TMPDIR:-/tmp}/check-docs-test.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# scaffold <stack> <ci-host> <dir> — a fresh scaffold of every seeded part, as the harness kit copies them.
scaffold() {
  local st=$1 ci=$2 dir=$3 part
  mkdir -p "$dir"
  for part in stack base agents settings late; do
    TC_STACK=$st TC_PART=$part bash "$SHARED/tc-copy.sh" "$dir" > /dev/null 2>&1
  done
  TC_STACK=$st TC_PART=ci TC_CI=$ci bash "$SHARED/tc-copy.sh" "$dir" > /dev/null 2>&1
  TC_STACK=$st TC_PART=tail bash "$SHARED/tc-copy.sh" "$dir" > /dev/null 2>&1
  TC_STACK=$st TC_PART=manifest bash "$SHARED/tc-copy.sh" "$dir" > /dev/null 2>&1
}

# run_check <dir> [args...] — runs the project's own copy; sets OUT and EC.
run_check() {
  local dir=$1
  shift
  OUT=$(cd "$dir" && bash scripts/check-docs.sh "$@" 2>&1)
  EC=$?
}

# expect_finding <dir> <description> <regex> — exit 1 and a file:line: finding matching the regex.
expect_finding() {
  run_check "$1"
  check 1 "$EC" "$2: exits 1"
  check 1 "$(printf '%s\n' "$OUT" | grep -cE "$3")" "$2: reports the finding ($OUT)"
}

# every stack scaffolds clean on GitHub; one stack per CI host proves the host-owned folders do not matter
for st in nextjs vite-react nestjs fastapi; do
  d="$T/clean-$st"
  scaffold "$st" github "$d"
  run_check "$d"
  check 0 "$EC" "clean_scaffold[$st]: exits 0 ($OUT)"
  check 1 "$([[ -x "$d/scripts/check-docs.sh" && -f "$d/docs/architecture.md" ]] && echo 1 || echo 0)" "clean_scaffold[$st]: script is executable and the codemap is seeded"
done
d="$T/clean-azure"
scaffold fastapi azure "$d"
run_check "$d"
check 0 "$EC" "clean_scaffold[azure]: exits 0 ($OUT)"

# the shared ts and py templates alone: the script runs against a bare project made from the shared layer
for variant in ts py; do
  d="$T/shared-$variant"
  mkdir -p "$d/scripts" "$d/docs"
  cp "$CHECK" "$d/scripts/check-docs.sh"
  printf '# p\n\nSee [arch](docs/architecture.md) and %s.\n' "${BT}docs/architecture.md${BT}" > "$d/README.md"
  printf '# Architecture\n' > "$d/docs/architecture.md"
  run_check "$d"
  check 0 "$EC" "shared_template[$variant]: exits 0 ($OUT)"
done

# faulted_scaffold <stack> <name> — a fresh clean scaffold to plant one fault in.
faulted() {
  local d="$T/fault-$2"
  rm -rf "$d"
  scaffold "$1" github "$d"
  echo "$d"
}

for st in nextjs fastapi; do
  d=$(faulted "$st" "link-$st")
  printf '\nSee [gone](docs/gone.md).\n' >> "$d/README.md"
  expect_finding "$d" "broken_link[$st]" '^README\.md:[0-9]+: broken link: docs/gone\.md$'

  d=$(faulted "$st" "path-$st")
  printf '\nSee %s.\n' "${BT}src/gone/file.ts${BT}" >> "$d/docs/architecture.md"
  expect_finding "$d" "missing_path[$st]" '^docs/architecture\.md:[0-9]+: path does not exist: src/gone/file\.ts$'
done

# a boundary README with a Contents heading
d=$(faulted nextjs contents)
mkdir -p "$d/src/features/billing"
printf '# billing\n\nPublic entry point: %s.\n\n## Contents\n\n- one\n' "${BT}src/features/billing/index.ts${BT}" > "$d/src/features/billing/README.md"
touch "$d/src/features/billing/index.ts"
expect_finding "$d" "contents_heading" '^src/features/billing/README\.md:[0-9]+: README has a Contents heading'

# a README naming every file of its own folder
d=$(faulted fastapi listing)
mkdir -p "$d/src/billing"
touch "$d/src/billing/a.py" "$d/src/billing/b.py" "$d/src/billing/c.py"
printf '# billing\n\n- [a](a.py)\n- [b](b.py)\n- %s\n' "${BT}src/billing/c.py${BT}" > "$d/src/billing/README.md"
expect_finding "$d" "lists_every_file" '^src/billing/README\.md:1: README lists every file of its folder'

# a README that names only some files is fine
d=$(faulted fastapi partial)
mkdir -p "$d/src/billing"
touch "$d/src/billing/a.py" "$d/src/billing/b.py" "$d/src/billing/c.py"
printf '# billing\n\nEntry point: [a](a.py).\n' > "$d/src/billing/README.md"
run_check "$d"
check 0 "$EC" "partial_listing: a README naming one file passes ($OUT)"

# web links, anchors, fenced paths, comments and generated folders are ignored
d=$(faulted nextjs ignored)
mkdir -p "$d/node_modules/pkg"
cat >> "$d/README.md" <<'MD'

[web](https://example.com/missing.md) [mail](mailto:a@b.c) [top](#run) [self](#nope)

```bash
cat src/not/there.ts
```

~~~
`src/also/not/there.ts` [x](nope.md)
~~~

<!-- `src/hidden/not/there.ts` [x](hidden.md) -->

A generated path: `node_modules/pkg/index.js` and `dist/out.js`.
MD
run_check "$d"
check 0 "$EC" "ignored_content: web links, anchors, fences, comments and generated folders pass ($OUT)"

# a link target with a space, written as %20, resolves to a real file
d=$(faulted nextjs spaces)
mkdir -p "$d/docs/my notes"
printf '# n\n' > "$d/docs/my notes/page one.md"
printf '\nSee [page](docs/my%%20notes/page%%20one.md) and [angle](<docs/my notes/page one.md>).\n' >> "$d/README.md"
run_check "$d"
check 0 "$EC" "path_with_spaces: encoded and angle-bracket links resolve ($OUT)"
printf '\nSee [bad](docs/my%%20notes/none%%20here.md).\n' >> "$d/README.md"
expect_finding "$d" "path_with_spaces_broken" '^README\.md:[0-9]+: broken link: docs/my notes/none here\.md$'

# the script works when the project folder itself has a space in its path
d="$T/space dir/proj"
mkdir -p "$d/scripts"
cp "$CHECK" "$d/scripts/check-docs.sh"
printf '# p\n\n[gone](nope.md)\n' > "$d/README.md"
run_check "$d"
check 1 "$EC" "project_path_with_space: exits 1"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^README\.md:3: broken link: nope\.md$')" "project_path_with_space: reports the finding ($OUT)"

# arguments limit the check to the named files (the pre-commit call)
d=$(faulted nextjs staged)
printf '\nSee [gone](docs/gone.md).\n' >> "$d/README.md"
run_check "$d" docs/architecture.md
check 0 "$EC" "staged_files: a fault outside the named files is not reported ($OUT)"
run_check "$d" README.md
check 1 "$EC" "staged_files: a fault in a named file is reported"

# output is capped at 20 lines, the last one saying how many findings were cut
d=$(faulted nextjs cap)
for i in $(seq 1 30); do printf '\nSee [gone%s](docs/gone%s.md).\n' "$i" "$i" >> "$d/README.md"; done
run_check "$d"
check 1 "$EC" "output_cap: exits 1"
check 20 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "output_cap: at most 20 lines"
check 1 "$(printf '%s\n' "$OUT" | tail -n 1 | grep -c '^check-docs: 11 more findings not shown$')" "output_cap: last line counts the rest ($OUT)"

# the lefthook and CI templates call the script, and the pre-push hook runs it in full
for lh in "$SHARED/template-ts/lefthook.yml" "$SHARED/template-py/lefthook.yml"; do
  n=$(basename "$(dirname "$lh")")
  check 1 "$(grep -c 'run: bash scripts/check-docs.sh {staged_files}$' "$lh")" "lefthook[$n]: pre-commit checks the staged Markdown"
  check 1 "$(grep -c 'run: bash scripts/check-docs.sh$' "$lh")" "lefthook[$n]: pre-push runs the full check"
done
for ci in "$SHARED/template-ci/github-ts/.github/workflows/ci.yml" "$SHARED/template-ci/github-py/.github/workflows/ci.yml"; do
  n=$(basename "$(dirname "$(dirname "$(dirname "$ci")")")")
  check 1 "$(grep -c 'run: bash scripts/check-docs.sh$' "$ci")" "ci[$n]: runs the docs check as a plain script step"
done
check 1 "$(grep -c -- '- bash: bash scripts/check-docs.sh$' "$SHARED/template-ci/azure/azure-pipelines/templatecentral-gates.yml")" "ci[azure]: runs the docs check as a plain script step"

# the retired gate and its opt-in appear nowhere in the seeded layer or the kit
old=$(grep -rnE 'readme-coupling|readme-freshness|skip-readme-check|ci-gates\.sh readme|richReadme|TC_RICH_README|README freshness' \
  "$REPO_ROOT/skills/scaffold" "$REPO_ROOT/skills/add" "$REPO_ROOT/skills/cleanup" "$REPO_ROOT/skills/review" "$REPO_ROOT/skills/standards" 2>/dev/null)
check "" "$old" "retired_gate: no trace in skills/"

echo "check-docs.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

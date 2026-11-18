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

# bare_project <name> — a project with only the script and a root README, outside any git repository.
bare_project() {
  local d="$T/bare-$1"
  rm -rf "$d"
  mkdir -p "$d/scripts" "$d/docs"
  cp "$CHECK" "$d/scripts/check-docs.sh"
  printf '# p\n' > "$d/docs/architecture.md"
  echo "$d"
}

# an internal failure exits 2 with one line naming the cause; exit 1 stays for findings
d=$(bare_project failclosed)
printf '# p\n' > "$d/README.md"
stub="$T/stub-mktemp"
mkdir -p "$stub"
printf '#!/bin/sh\nexit 1\n' > "$stub/mktemp"
chmod +x "$stub/mktemp"
OUT=$(cd "$d" && PATH="$stub:$PATH" bash scripts/check-docs.sh 2>&1)
EC=$?
check 2 "$EC" "mktemp_fails: exits 2"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^check-docs: cannot create a temporary folder')" "mktemp_fails: one line names the cause ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "mktemp_fails: exactly one line"

OUT=$(cd "$d" && PATH="$T/no-such-bin" /bin/bash scripts/check-docs.sh 2>&1)
EC=$?
check 2 "$EC" "missing_tool: exits 2"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^check-docs: missing tool: awk$')" "missing_tool: names the tool ($OUT)"

if [[ "$(id -u)" -ne 0 ]]; then
  chmod 000 "$d/README.md"
  run_check "$d"
  chmod 644 "$d/README.md"
  check 2 "$EC" "unreadable_file: exits 2"
  check 1 "$(printf '%s\n' "$OUT" | grep -c '^check-docs: cannot read README\.md$')" "unreadable_file: names the file ($OUT)"
fi

d=$(bare_project gitfail)
git init -q "$d"
printf '# p\n\n[gone](nope.md)\n' > "$d/README.md"
stub="$T/stub-git"
mkdir -p "$stub"
cat > "$stub/git" <<EOF
#!/bin/sh
if [ "\$1" = check-ignore ]; then echo "fatal: boom" >&2; exit 128; fi
exec "$(command -v git)" "\$@"
EOF
chmod +x "$stub/git"
OUT=$(cd "$d" && PATH="$stub:$PATH" bash scripts/check-docs.sh 2>&1)
EC=$?
check 2 "$EC" "git_check_ignore_fails: exits 2"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^check-docs: git check-ignore failed: fatal: boom$')" "git_check_ignore_fails: names the cause ($OUT)"

# no process is started per reference: 4000 references finish well inside the bound
d=$(bare_project speed)
{
  printf '# p\n\n'
  for i in $(seq 1 2000); do printf -- '- [l%s](docs/architecture.md) and %sdocs/architecture.md%s\n' "$i" "$BT" "$BT"; done
} > "$d/README.md"
start=$SECONDS
run_check "$d"
elapsed=$((SECONDS - start))
check 0 "$EC" "speed_4000_refs: exits 0 ($OUT)"
check 1 "$([[ $elapsed -lt 10 ]] && echo 1 || echo 0)" "speed_4000_refs: finished in ${elapsed}s, bound 10s"
for i in $(seq 1 2000); do printf '[b%s](docs/gone%s.md)\n' "$i" "$i"; done > "$d/docs/broken.md"
start=$SECONDS
run_check "$d" docs/broken.md
elapsed=$((SECONDS - start))
check 1 "$EC" "speed_2000_broken: exits 1"
check 20 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "speed_2000_broken: output capped"
check 1 "$([[ $elapsed -lt 10 ]] && echo 1 || echo 0)" "speed_2000_broken: finished in ${elapsed}s, bound 10s"

# a URL scheme is external whatever its case
d=$(bare_project schemes)
printf '# p\n\n[a](HTTPS://X.com/missing) [b](Mailto:a@b.c) [c](custom+x-1.y:rest) [d](FTP://h/f)\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "url_schemes_any_case: external links pass ($OUT)"
printf '\n[e](Docs/Gone.md)\n' >> "$d/README.md"
expect_finding "$d" "url_schemes_relative_still_checked" '^README\.md:[0-9]+: broken link: Docs/Gone\.md$'

# a fence closes only on the same character with at least the opening length
d=$(bare_project fences)
{
  printf '# p\n\n%smd\n%s\n[inner](gone-inner.md)\n%s\n[still](gone-still.md)\n~~~\n[tilde](gone-tilde.md)\n%s\n\n' "$BT$BT$BT$BT" "$BT$BT$BT" "$BT$BT$BT" "$BT$BT$BT$BT"
  printf '[after](gone-after.md)\n'
} > "$d/README.md"
run_check "$d"
check 1 "$EC" "fence_length: exits 1"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^README\.md:12: broken link: gone-after\.md$')" "fence_length: only the link after the real close is reported ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "fence_length: nothing inside the longer fence is reported ($OUT)"

# double-backtick spans, even around a single backtick, are not scanned
d=$(bare_project spans)
printf '# p\n\nA %ssee %ssrc/not/there.ts%s here%s and %s[x](gone.md)%s and %s%s%s.\n' "$BT$BT" "$BT" "$BT" "$BT$BT" "$BT$BT" "$BT$BT" "$BT$BT" "$BT" "$BT$BT" > "$d/README.md"
printf 'Plain %ssrc/not/there.ts%s stays checked.\n' "$BT" "$BT" >> "$d/README.md"
expect_finding "$d" "double_backtick_spans" '^README\.md:4: path does not exist: src/not/there\.ts$'
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "double_backtick_spans: only the plain span is reported ($OUT)"

# every %XX sequence is decoded before the existence test
d=$(bare_project percent)
printf '# n\n' > "$d/docs/a.b.md"
printf '# n\n' > "$d/docs/$(printf '\342\202\254').md"
printf '# p\n\n[a](docs/a%%2Eb.md) [e](docs/%%E2%%82%%AC.md) [lone](docs/100%%.md)\n' > "$d/README.md"
expect_finding "$d" "percent_decoding" '^README\.md:3: broken link: docs/100%\.md$'
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "percent_decoding: encoded dot and multibyte names resolve ($OUT)"

# a README naming every file as a plain item, bold item or table row is flagged
for form in plain bold table; do
  d=$(bare_project "listing-$form")
  mkdir -p "$d/src/billing"
  touch "$d/src/billing/index.ts" "$d/src/billing/b.ts" "$d/src/billing/c.ts"
  case "$form" in
    plain) printf '# billing\n\n- index.ts: entry\n- b.ts: b\n- c.ts: c\n' > "$d/src/billing/README.md" ;;
    bold) printf '# billing\n\n- **index.ts** entry\n- **b.ts** b\n* **c.ts**: c\n' > "$d/src/billing/README.md" ;;
    table) printf '# billing\n\n| File | Role |\n|---|---|\n| %sindex.ts%s | entry |\n| %sb.ts%s | b |\n| c.ts | c |\n' "$BT" "$BT" "$BT" "$BT" > "$d/src/billing/README.md" ;;
  esac
  expect_finding "$d" "listing_$form" '^src/billing/README\.md:1: README lists every file of its folder'
done

# a README naming its entry point and one other file is fine, and so is a folder with fewer than 3 files
d=$(bare_project listing-partial)
mkdir -p "$d/src/billing" "$d/src/small"
touch "$d/src/billing/index.ts" "$d/src/billing/b.ts" "$d/src/billing/c.ts" "$d/src/small/a.ts" "$d/src/small/b.ts"
printf '# billing\n\n- index.ts: entry\n- b.ts: helper\n' > "$d/src/billing/README.md"
printf '# small\n\n- a.ts: a\n- b.ts: b\n' > "$d/src/small/README.md"
run_check "$d"
check 0 "$EC" "listing_partial_and_small: not flagged ($OUT)"

# Markdown under every folder the script skips is ignored, read from the script's own lists
skips=$(sed -n -e "s/^GENERATED='\(.*\)'\$/\1/p" -e "s/^SKIPPED_DIRS='\(.*\)'\$/\1/p" "$CHECK")
check 1 "$([[ $(printf '%s\n' "$skips" | wc -w | tr -d ' ') -ge 15 ]] && echo 1 || echo 0)" "skipped_folders: the lists were read from the script ($skips)"
d=$(bare_project skipped)
for folder in $skips; do
  mkdir -p "$d/pkg/$folder/deep"
  printf '# x\n\n[gone](nope.md)\n' > "$d/pkg/$folder/README.md"
  printf '# x\n\n[gone](nope.md)\n' > "$d/pkg/$folder/deep/README.md"
  mkdir -p "$d/docs/$folder"
  printf '# x\n\n[gone](nope.md)\n' > "$d/docs/$folder/page.md"
done
printf '# p\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "skipped_folders: full run ignores Markdown under every skipped folder ($OUT)"
for folder in $skips; do
  run_check "$d" "pkg/$folder/README.md" "pkg/$folder/deep/README.md" "docs/$folder/page.md"
  check 0 "$EC" "skipped_folders[$folder]: named files are ignored ($OUT)"
done
mkdir -p "$d/pkg/keep"
printf '# x\n\n[gone](nope.md)\n' > "$d/pkg/keep/README.md"
run_check "$d"
check 1 "$EC" "skipped_folders: a folder outside the lists is still checked"

# the retired gate and its opt-in appear nowhere in the seeded layer or the kit
old=$(grep -rnE 'readme-coupling|readme-freshness|skip-readme-check|ci-gates\.sh readme|richReadme|TC_RICH_README|README freshness' \
  "$REPO_ROOT/skills/scaffold" "$REPO_ROOT/skills/add" "$REPO_ROOT/skills/cleanup" "$REPO_ROOT/skills/review" "$REPO_ROOT/skills/standards" 2>/dev/null)
check "" "$old" "retired_gate: no trace in skills/"

echo "check-docs.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

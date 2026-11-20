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
  printf '# project\n\nA test project.\n\n## Run\n\n## Test\n\n## Build\n' > "$dir/README.md"
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

# no root README.md: the whole-project run fails and names the file; a run on named files does not require it
d="$T/no-readme"
scaffold fastapi github "$d"
rm "$d/README.md"
expect_finding "$d" "missing_readme" '^README\.md:1: missing; create README\.md'
run_check "$d" docs/architecture.md
check 0 "$EC" "missing_readme: a run on named files exits 0 ($OUT)"

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
  printf '# p\n' > "$d/README.md"
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
printf '# p\n\n[a](HTTPS://X.com/missing) [b](Mailto:a@b.c) [c](custom+x-1.y://rest) [d](FTP://h/f)\n' > "$d/README.md"
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

# proj <name> — a bare project with src/real.ts and src/lib/db.ts.
proj() {
  local d
  d=$(bare_project "$1")
  mkdir -p "$d/src/lib"
  touch "$d/src/real.ts" "$d/src/lib/db.ts"
  echo "$d"
}

# a CRLF file gives the same results as its LF form: fences close, reference targets are clean, Contents and listings fire
FENCE3="$BT$BT$BT"
d=$(proj crlf-fence)
printf '[ref][r]\r\n[r]: ../src/real.ts\r\n%s\r\n[x](../src/inf.ts)\r\n%s\r\n[c](../src/after.ts)\r\n' "$FENCE3" "$FENCE3" > "$d/docs/crlf.md"
run_check "$d"
check 1 "$EC" "crlf_fence_and_reference: exits 1 ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^docs/crlf\.md:6: broken link: \.\./src/after\.ts$')" "crlf_fence_and_reference: link after the fence is checked ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "crlf_fence_and_reference: the reference target and the fenced link are clean ($OUT)"
d=$(proj crlf-contents)
printf '# T\r\n## Contents\r\n' > "$d/README.md"
expect_finding "$d" "crlf_contents_heading" '^README\.md:2: README has a Contents heading'
d=$(proj crlf-listing)
mkdir -p "$d/m"
touch "$d/m/a.ts" "$d/m/b.ts" "$d/m/c.ts"
printf '# M\r\n- a.ts\r\n- b.ts\r\n- c.ts\r\n' > "$d/m/README.md"
expect_finding "$d" "crlf_listing" '^m/README\.md:1: README lists every file of its folder'

# a footnote definition is not a link definition; a label with prose is not one either; real definitions are checked
d=$(proj refdefs)
printf '[^1]: note\n[Label]: some prose here\n[ok]: src/real.ts "title"\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "footnote_and_prose_label: not reported ($OUT)"
printf '[r]: src/gone.md\n[r2]: ./gone2\n[r3]: gone3.md "title"\n' > "$d/README.md"
run_check "$d"
check 3 "$(printf '%s\n' "$OUT" | grep -c 'broken link')" "reference_definitions_checked: three real definitions are reported ($OUT)"

# an angle-bracket target keeps its spaces, in a reference definition and in an inline link
d=$(proj angle)
printf '# p\n' > "$d/src/a b.ts"
printf '[r]: <src/a b.ts>\n[l](<src/a b.ts>)\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "angle_target_with_space: existing target resolves ($OUT)"
printf '[r]: <src/c d.ts>\n[l](<src/c d.ts>)\n' > "$d/README.md"
run_check "$d"
check 2 "$(printf '%s\n' "$OUT" | grep -c 'broken link: src/c d\.ts$')" "angle_target_with_space: missing target reported whole in both forms ($OUT)"

# a fence inside a blockquote is a fence; indented code is not scanned, a list continuation is
d=$(proj blockquote)
printf '> %s\n> [x](src/bq.ts)\n> %s\n' "$FENCE3" "$FENCE3" > "$d/README.md"
run_check "$d"
check 0 "$EC" "blockquote_fence: link inside is ignored ($OUT)"
printf 'Text\n\n    [i](src/ind.ts)\n\n\t[t](src/tab.ts)\n\n- item\n\n    [c](src/cont.ts)\n' > "$d/README.md"
run_check "$d"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "indented_code: only the list continuation is scanned ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^README\.md:9: broken link: src/cont\.ts$')" "indented_code: the list continuation is reported ($OUT)"

# inline code holding a comment opener does not hide the rest of the file; a same-line triple backtick is inline code
d=$(proj inline-comment)
printf 'Use %s<!--%s to open.\n[x](src/hidden.ts)\n' "$BT" "$BT" > "$d/README.md"
expect_finding "$d" "inline_comment_opener" '^README\.md:2: broken link: src/hidden\.ts$'
printf '%sx%s\n[y](src/same.ts)\n' "$FENCE3" "$FENCE3" > "$d/README.md"
expect_finding "$d" "same_line_triple_backtick" '^README\.md:2: broken link: src/same\.ts$'
printf '<!-- hidden [h](src/h.ts) -->\n[v](src/v.ts)\n' > "$d/README.md"
expect_finding "$d" "real_comment_still_hides" '^README\.md:2: broken link: src/v\.ts$'

# a link starting with a slash is a site route and is not checked
d=$(proj routes)
printf '[login](/login) [home](/)\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "root_absolute_link: not checked ($OUT)"

# an explicit file that does not exist is an internal failure
d=$(proj missing-arg)
printf '# p\n' > "$d/README.md"
run_check "$d" nonexist.md
check 2 "$EC" "missing_file_argument: exits 2"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^check-docs: no such file: nonexist\.md$')" "missing_file_argument: names the file ($OUT)"

# one very long line is scanned in linear time
d=$(proj longline)
pad=$(printf 'x%.0s' $(seq 1 100))
for i in $(seq 1 20000); do printf '[%s%s](src/real.ts)' "$pad" "$i"; done > "$d/README.md"
start=$SECONDS
run_check "$d"
elapsed=$((SECONDS - start))
check 0 "$EC" "long_line_20000_links: exits 0 ($OUT)"
check 1 "$([[ $elapsed -lt 10 ]] && echo 1 || echo 0)" "long_line_20000_links: finished in ${elapsed}s, bound 10s"

# a backticked path without an extension passes when a file of that stem or a folder of that name exists
d=$(proj stem)
printf 'See %ssrc/lib/db%s and %ssrc/lib%s and %ssrc/lib/missing%s.\n' "$BT" "$BT" "$BT" "$BT" "$BT" "$BT" > "$d/README.md"
expect_finding "$d" "extensionless_stem" '^README\.md:1: path does not exist: src/lib/missing$'
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "extensionless_stem: only the missing path is reported ($OUT)"
printf '[l](src/lib/db)\n' > "$d/README.md"
expect_finding "$d" "extensionless_link_stays_exact" '^README\.md:1: broken link: src/lib/db$'

# link-like prose is not a link: subscripts, escaped brackets, regex text and code spans
d=$(proj link-prose)
printf 'idx arr[0](1) and \\[x\\](nope.md) and [a-z](\\d+) and %s[x](nope.md)%s.\n' "$BT" "$BT" > "$d/README.md"
run_check "$d"
check 0 "$EC" "link_like_prose: not reported ($OUT)"
printf '[![i](src/gone.ts)](src/real.ts) [t](src/real.ts "title") [p](src/real.ts)\n' > "$d/README.md"
expect_finding "$d" "nested_image_link" '^README\.md:1: broken link: src/gone\.ts$'
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "nested_image_link: only the missing target is reported ($OUT)"

# a target with a colon is a path unless it has a real scheme
d=$(proj schemes-narrow)
printf '[x](nope.md:3) [y](src/real.ts:3)\n' > "$d/README.md"
run_check "$d"
check 2 "$(printf '%s\n' "$OUT" | grep -cE '^README\.md:1: broken link: (nope\.md|src/real\.ts):3$')" "path_line_is_a_path: path:line is checked as a path ($OUT)"
printf '[a](custom+x-1.y://h/p) [b](tel:+123) [c](data:text/plain,x) [d](urn:isbn:1) [e](javascript:void(0)) [f](git+ssh://h/r)\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "real_schemes: external forms pass ($OUT)"

# an unterminated link is not a link
d=$(proj unterminated)
printf '[b](nope.md\n[c](nope.md "title\n[d](<nope.md\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "unterminated_link: not reported ($OUT)"

# a label with prose is not a reference definition; a backticked path before . or ) is checked as written
d=$(proj status-label)
printf '[Status]: Done\n[Status]: Done.\n[Owner]: team\n(see %ssrc/real.ts%s). Then %ssrc/real.ts%s.\n' "$BT" "$BT" "$BT" "$BT" > "$d/README.md"
run_check "$d"
check 0 "$EC" "status_label_and_trailing_punctuation: not reported ($OUT)"
printf '[r]: gone.md\n(see %ssrc/gone.ts%s).\n' "$BT" "$BT" > "$d/README.md"
run_check "$d"
check 2 "$(printf '%s\n' "$OUT" | grep -cE 'broken link: gone\.md$|path does not exist: src/gone\.ts$')" "real_definition_and_span_before_paren: reported ($OUT)"

# an indented line right after a heading is indented code
d=$(proj heading-indent)
printf '# T\n    [i](src/ind.ts)\n## U\n\t[t](src/tab.ts)\nText\n    [lazy](src/lazy.ts)\n' > "$d/README.md"
expect_finding "$d" "indent_after_heading" '^README\.md:6: broken link: src/lazy\.ts$'
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "indent_after_heading: only the paragraph continuation is scanned ($OUT)"

# a byte-order mark does not hide the Contents heading rule on the first line
d=$(proj bom)
printf '\357\273\277## Contents\n' > "$d/README.md"
expect_finding "$d" "bom_contents_heading" '^README\.md:1: README has a Contents heading'
printf '\357\273\277[x](src/gone.ts)\n' > "$d/README.md"
expect_finding "$d" "bom_first_line_link" '^README\.md:1: broken link: src/gone\.ts$'

# path rule: a path a doc names that does not exist is stale, unless it is an example (placeholder, ellipsis, path/to)
d=$(proj stale-rule)
printf '%ssrc/utils%s %ssrc/lib/missing%s\n' "$BT" "$BT" "$BT" "$BT" > "$d/README.md"
run_check "$d"
check 2 "$(printf '%s\n' "$OUT" | grep -cE 'path does not exist: (src/utils|src/lib/missing)$')" "stale_path: a missing path under an existing folder is reported ($OUT)"
printf '%snolib/utils%s %spath/to/file.ts%s %ssrc/<name>/x.ts%s %ssrc/.../x.ts%s\n' "$BT" "$BT" "$BT" "$BT" "$BT" "$BT" "$BT" "$BT" > "$d/README.md"
run_check "$d"
check 0 "$EC" "example_paths: unknown folder, path/to, placeholder and ellipsis pass ($OUT)"

# arguments resolve against the caller's folder; absolute paths inside the project work; outside paths are refused
d=$(proj args)
printf '# p\n\n[gone](nope.md)\n' > "$d/README.md"
OUT=$(cd "$T" && bash "$d/scripts/check-docs.sh" "$d/README.md" 2>&1)
EC=$?
check 1 "$EC" "absolute_argument: exits 1 ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^README\.md:3: broken link: nope\.md$')" "absolute_argument: reported against the project path ($OUT)"
OUT=$(cd "$d/docs" && bash ../scripts/check-docs.sh ../README.md 2>&1)
EC=$?
check 1 "$EC" "caller_relative_argument: exits 1 ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^README\.md:3: broken link: nope\.md$')" "caller_relative_argument: resolved against the caller folder ($OUT)"
ln -s "$d" "$T/args-link"
OUT=$(cd "$T" && bash "$T/args-link/scripts/check-docs.sh" "$d/README.md" 2>&1)
EC=$?
check 1 "$EC" "symlinked_project_path: exits 1 ($OUT)"
printf '# o\n' > "$T/outside.md"
for arg in "$T/outside.md" ../outside.md; do
  OUT=$(cd "$d" && bash scripts/check-docs.sh "$arg" 2>&1)
  EC=$?
  check 2 "$EC" "outside_argument[$arg]: exits 2"
  check 1 "$(printf '%s\n' "$OUT" | grep -c '^check-docs: outside the project: ')" "outside_argument[$arg]: one clear line ($OUT)"
done

# a link target that is not a repository path is skipped: host:port, user@host:path, scheme: with a non-digit
d=$(proj link-targets)
printf '[a](localhost:3000) [b](localhost:3000/x) [c](example.com:8080) [d](slack:open) [e](vscode:extension/x) [f](obsidian:open) [g](git@host:o/r)\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "non_path_targets: host:port, user@host, scheme: pass ($OUT)"
printf '[a](nope.md:3) [b](custom+x-1.y:rest) [c](src/real.ts:3) [d](note: text)\n' > "$d/README.md"
run_check "$d"
check 4 "$(printf '%s\n' "$OUT" | grep -cE '^README\.md:1: broken link: (nope\.md:3|custom\+x-1\.y:rest|src/real\.ts:3|note:)$')" "path_like_colon_targets: still checked as paths ($OUT)"

# a space inside the parentheses does not hide the target
d=$(proj link-spaces)
printf '[x]( missing.md )\n[y](  src/gone.ts  "t")\n[z]( src/real.ts )\n' > "$d/README.md"
run_check "$d"
check 2 "$(printf '%s\n' "$OUT" | grep -cE '^README\.md:[12]: broken link: (missing\.md|src/gone\.ts)$')" "link_with_inner_spaces: trimmed and checked ($OUT)"
check 1 "$EC" "link_with_inner_spaces: exits 1"

# an ellipsis exempts only a whole path segment
d=$(proj ellipsis)
printf '%ssrc/x...y.ts%s %ssrc/lib/gone.ts...%s\n' "$BT" "$BT" "$BT" "$BT" > "$d/README.md"
run_check "$d"
check 2 "$(printf '%s\n' "$OUT" | grep -cE 'path does not exist: (src/x\.\.\.y\.ts|src/lib/gone\.ts\.\.\.)$')" "ellipsis_inside_name: reported ($OUT)"
printf '%ssrc/.../x.ts%s %ssrc/lib/foo\342\200\246/x.ts%s %s.../x.ts%s\n' "$BT" "$BT" "$BT" "$BT" "$BT" "$BT" > "$d/README.md"
run_check "$d"
check 0 "$EC" "ellipsis_segment: whole-segment examples pass ($OUT)"

# a long target is cut in the report, on a character boundary
d=$(proj long-target)
long=$(awk 'BEGIN { for (i = 0; i < 20000; i++) printf "aaaaaaaaaa"; }')
printf '[x](%s.md)\n' "$long" > "$d/README.md"
run_check "$d"
check 1 "$EC" "long_target: exits 1"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "long_target: one line"
check 1 "$([ "$(printf '%s' "$OUT" | wc -c | tr -d ' ')" -le 200 ] && echo 1 || echo 0)" "long_target: the line stays short ($(printf '%s' "$OUT" | wc -c))"
mb=$(awk 'BEGIN { for (i = 0; i < 100; i++) printf "\303\251"; }')
printf '[x](a%s.md)\n' "$mb" > "$d/README.md"
run_check "$d"
want="README.md:1: broken link: a$(awk 'BEGIN { for (i = 0; i < 59; i++) printf "\303\251"; }')..."
check "$want" "$OUT" "long_target_utf8: cut between characters"
check 0 "$(printf '%s' "$OUT" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; echo $?)" "long_target_utf8: output is valid UTF-8"

# a target with a backslash is not checked
d=$(proj backslash)
printf '[a](docs\\real.md) [b](C:\\x)\n' > "$d/README.md"
run_check "$d"
check 0 "$EC" "backslash_targets: not checked ($OUT)"

# the retired gate and its opt-in appear nowhere in the seeded layer or the kit
old=$(grep -rnE 'readme-coupling|readme-freshness|skip-readme-check|ci-gates\.sh readme|richReadme|TC_RICH_README|README freshness' \
  "$REPO_ROOT/skills/scaffold" "$REPO_ROOT/skills/add" "$REPO_ROOT/skills/cleanup" "$REPO_ROOT/skills/review" "$REPO_ROOT/skills/standards" 2>/dev/null)
check "" "$old" "retired_gate: no trace in skills/"

echo "check-docs.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

#!/usr/bin/env bash
# Bundle-size budget for nextjs and vite-react: after a build, the gzip size of the emitted JS and CSS must stay within max_gzip_kb in .claude/bundle-budget.txt.
# Reads the build output only (.next/static for Next.js, dist for Vite): no network. The frontend folder is the current one, or BUNDLE_DIR when it sits in a subfolder.
# A folder with no next.config.* or vite.config.* exits 0 with a one-line reason, unless its package.json depends on next or vite, or .claude/harness.json records the stack as nextjs or vite-react: that fails, it never passes silently.
# The stack comes from harness.json, which the gate ratchet freezes as content and verify-harness.sh hashes, so moving the app into a subfolder cannot turn the gate into a skip: set BUNDLE_DIR to the frontend folder.
# The folder read is fixed (.next/static for Next.js, dist for Vite) and a tracked dist or .next is refused, so the gate measures a fresh build only: ci-gates.sh deletes both before it builds, and a build that wrote elsewhere leaves nothing to measure and exits 2.
# Will not catch: a build that emits a large bundle some other way than into those folders (a second output, a server-rendered payload), or a harness.json whose frozen "stack" was wrong from the start (the ratchet and verify-harness only catch a change to it).
# Exit: 0 within budget (or no browser bundle), 1 over budget, 2 it could not measure (no build, bad budget, unreadable output).
# A trailing '# comment' on the budget line is allowed. A second max_gzip_kb line or a carriage return in the budget file is refused. In CI the budget-file override is refused.
# With --build the gate first deletes dist and .next in the frontend folder and runs pnpm run build there, so a stale folder (after outDir moved, or a leftover build) can never pass; ci-gates.sh and the pre-push hook both run it this way, one shared path. Without it the gate measures what is already built.
# A harness.json that exists but records no parsable "stack" is refused (exit 2), as is a missing one: the stack is never guessed. Stacks with no browser bundle (nestjs, fastapi) record themselves and skip with a reason.
# Usage: bash scripts/check-bundle-size.sh [--build]        Env: BUNDLE_DIR frontend folder, BUNDLE_BUDGET_FILE budget file path (relative paths start at the folder you run this from).
set -uo pipefail
export LC_ALL=C

die() {
  printf 'check-bundle-size: %s\n' "$1" >&2
  exit 2
}

# The budget file path can widen the gate, so it is not allowed in GitHub Actions or Azure Pipelines.
if [ -n "${BUNDLE_BUDGET_FILE:-}" ]; then
  case "${GITHUB_ACTIONS:-}${TF_BUILD:-}" in
    *[Tt][Rr][Uu][Ee]*) die "BUNDLE_BUDGET_FILE is set, which can widen the gate. It is not allowed in CI: change .claude/bundle-budget.txt and review the change." ;;
  esac
fi

build=0
case "${1:-}" in
  '') ;;
  --build) build=1 ;;
  *) die "unknown argument '$1'. Usage: check-bundle-size.sh [--build]" ;;
esac

root=$PWD
budget_file=${BUNDLE_BUDGET_FILE:-.claude/bundle-budget.txt}
case "$budget_file" in
  /*) ;;
  *) budget_file=$root/$budget_file ;;
esac

if [ -n "${BUNDLE_DIR:-}" ]; then
  cd "$BUNDLE_DIR" 2> /dev/null || die "BUNDLE_DIR '$BUNDLE_DIR' is not a folder."
fi

# The stack recorded when the harness was seeded (a frozen file). A missing file, or one with no parsable "stack", is refused: with the stack unknown the gate could skip a project that does emit a bundle.
if [ ! -f "$root/.claude/harness.json" ]; then die "$root/.claude/harness.json is missing, so the stack is unknown and the gate cannot tell whether this project emits a bundle. Restore it with the harness refresh (templatecentral:migrate)."; fi
recorded=$(sed -n '/"stack"[[:space:]]*:/{s/^.*"stack"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p;q;}' "$root/.claude/harness.json") || die "cannot read $root/.claude/harness.json"
case "$recorded" in
  nextjs | vite-react | nestjs | fastapi) ;;
  *) die "$root/.claude/harness.json has no \"stack\" of nextjs, vite-react, nestjs or fastapi (got '$recorded'), so the gate cannot tell whether this project emits a bundle. Restore the file with the harness refresh (templatecentral:migrate)." ;;
esac

if ls next.config.* > /dev/null 2>&1; then
  stack=nextjs
  dir=.next/static
elif ls vite.config.* > /dev/null 2>&1; then
  stack=vite-react
  dir=dist
elif [ -f package.json ] && grep -qE '"(next|vite)"[[:space:]]*:' package.json; then
  die "package.json depends on next or vite, but there is no next.config.* or vite.config.* in ${BUNDLE_DIR:-the current folder}. Run this from the frontend folder, or set BUNDLE_DIR to it."
else
  case "$recorded" in
    nextjs | vite-react) die ".claude/harness.json records the stack as $recorded, but there is no next.config.* or vite.config.* in ${BUNDLE_DIR:-the current folder}. Run this from the frontend folder, or set BUNDLE_DIR to it." ;;
  esac
  echo "check-bundle-size: skipped, only nextjs and vite-react projects emit a browser bundle to measure."
  exit 0
fi

# Build output that git tracks is not a build: refuse it before reading anything from it.
tracked=$(git ls-files -- dist .next 2> /dev/null) || tracked=''
if [ -n "$tracked" ]; then die "build output is tracked by git (${tracked%%$'\n'*}). Remove it from git (git rm -r --cached dist .next) and add both to .gitignore: the gate measures a fresh build only."; fi

if [ "$build" = 1 ]; then
  rm -rf dist .next
  pnpm run build || die "the build failed, so the bundle size cannot be measured (output above)."
fi

if [ ! -f "$budget_file" ]; then die "$budget_file is missing. Restore it from the scaffold: it holds 'max_gzip_kb <number>'."; fi
if grep -q "$(printf '\r')" "$budget_file"; then die "carriage return in $budget_file: save it with LF line endings."; fi
if [ "$(awk '$1 == "max_gzip_kb" { n++ } END { print n + 0 }' "$budget_file")" -gt 1 ]; then die "$budget_file has more than one max_gzip_kb line: keep exactly one."; fi
max_kb=$(awk '$1 == "max_gzip_kb" { $1 = ""; sub(/#.*$/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$budget_file") || die "cannot read $budget_file"
case "$max_kb" in
  '' | *[!0-9]* | 0* | [0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) die "$budget_file needs a line 'max_gzip_kb <whole number above 0, 6 digits at most, no leading zeros>', for example 'max_gzip_kb 400' (got '$max_kb')." ;;
esac
if [ ! -d "$dir" ]; then die "no build output at $dir. Build first (pnpm build), then run this again."; fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-bundle-size.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

find "$dir" -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.css' \) -print > "$tmp/files.txt" 2> "$tmp/err.txt" || die "cannot read the build output under $dir: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
: > "$tmp/sizes.txt"
while IFS= read -r f; do
  gzip -n -9 -c "$f" > "$tmp/one.gz" 2> "$tmp/err.txt" || die "cannot compress $f: $(head -n 1 "$tmp/err.txt")"
  printf '%s\t%s\n' "$(wc -c < "$tmp/one.gz" | tr -d ' ')" "$f" >> "$tmp/sizes.txt"
done < "$tmp/files.txt"

if [ ! -s "$tmp/sizes.txt" ]; then die "no .js or .css files under $dir. Build first (pnpm build), then run this again."; fi

total=$(awk -F '\t' '{ s += $1 } END { print s + 0 }' "$tmp/sizes.txt") || die "cannot add up the file sizes"
budget=$((max_kb * 1024))
total_kb=$(((total + 1023) / 1024))
if [ "$total" -gt "$budget" ]; then
  printf 'check-bundle-size: %s emits %s bytes gzip of JS and CSS (%s KB rounded up; budget %s KB in %s).\n' "$stack" "$total" "$total_kb" "$max_kb" "$budget_file" >&2
  printf 'check-bundle-size: biggest files:\n' >&2
  sort -rn "$tmp/sizes.txt" > "$tmp/sizes-sorted.txt"
  head -n 5 "$tmp/sizes-sorted.txt" | while IFS="$(printf '\t')" read -r n p; do printf 'check-bundle-size:   %s KB  %s\n' "$(((n + 1023) / 1024))" "$p" >&2; done
  printf 'check-bundle-size: lazy-load heavy routes with a dynamic import, or drop or swap the large dependency. Raise max_gzip_kb only after a human decision.\n' >&2
  exit 1
fi
echo "check-bundle-size: ok ($stack, $total_kb KB gzip of JS and CSS rounded up, budget $max_kb KB)"

#!/usr/bin/env bash
# Bundle-size budget for nextjs and vite-react: after a build, the gzip size of the emitted JS and CSS must stay within max_gzip_kb in .claude/bundle-budget.txt.
# Reads the build output only (.next/static for Next.js, dist for Vite): no network. Other stacks exit 0 with a one-line reason.
# Usage: bash scripts/check-bundle-size.sh        Env: BUNDLE_BUDGET_FILE overrides the budget file path.
set -uo pipefail
export LC_ALL=C

budget_file=${BUNDLE_BUDGET_FILE:-.claude/bundle-budget.txt}

die() {
  printf 'check-bundle-size: %s\n' "$1" >&2
  exit 1
}

if ls next.config.* > /dev/null 2>&1; then
  stack=nextjs
  dir=.next/static
elif ls vite.config.* > /dev/null 2>&1; then
  stack=vite-react
  dir=dist
else
  echo "check-bundle-size: skipped, only nextjs and vite-react projects emit a browser bundle to measure."
  exit 0
fi

if [ ! -f "$budget_file" ]; then die "$budget_file is missing. Restore it from the scaffold: it holds 'max_gzip_kb <number>'."; fi
max_kb=$(awk '$1 == "max_gzip_kb" { print $2; exit }' "$budget_file")
case "$max_kb" in
  '' | *[!0-9]* | 0) die "$budget_file needs a line 'max_gzip_kb <whole number above 0>' (got '$max_kb')." ;;
esac
if [ ! -d "$dir" ]; then die "no build output at $dir. Build first (pnpm build), then run this again."; fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-bundle-size.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

find "$dir" -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.css' \) -print > "$tmp/files.txt" 2> /dev/null
: > "$tmp/sizes.txt"
while IFS= read -r f; do
  size=$(gzip -n -9 -c "$f" | wc -c | tr -d ' ') || die "cannot compress $f"
  printf '%s\t%s\n' "$size" "$f" >> "$tmp/sizes.txt"
done < "$tmp/files.txt"

if [ ! -s "$tmp/sizes.txt" ]; then die "no .js or .css files under $dir. Build first (pnpm build), then run this again."; fi

total=$(awk -F '\t' '{ s += $1 } END { print s + 0 }' "$tmp/sizes.txt")
budget=$((max_kb * 1024))
if [ "$total" -gt "$budget" ]; then
  printf 'check-bundle-size: %s emits %s KB gzip of JS and CSS (budget %s KB in %s).\n' "$stack" "$((total / 1024))" "$max_kb" "$budget_file" >&2
  printf 'check-bundle-size: biggest files:\n' >&2
  sort -rn "$tmp/sizes.txt" | head -n 5 | while IFS="$(printf '\t')" read -r n p; do printf 'check-bundle-size:   %s KB  %s\n' "$((n / 1024))" "$p" >&2; done
  printf 'check-bundle-size: lazy-load heavy routes with a dynamic import, or drop or swap the large dependency. Raise max_gzip_kb only after a human decision.\n' >&2
  exit 1
fi
echo "check-bundle-size: ok ($stack, $((total / 1024)) KB gzip of JS and CSS, budget $max_kb KB)"

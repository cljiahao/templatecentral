#!/usr/bin/env bash
# .env.example drift check: the variable names the code reads must match the keys in .env.example.
# Reads source files and .env.example only, never a real .env. Usage: bash scripts/check-env-example.sh
set -uo pipefail

example=.env.example
if [ ! -f "$example" ]; then
  echo "check-env-example: $example is missing. Create it and list every variable the code reads (use '# NAME=' for an optional one)." >&2
  exit 1
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/env-example.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C

# Names every runtime or build tool sets itself: not configuration the project owns.
builtin='^(NODE_ENV|CI|TZ|HOME|PATH|PWD|DEV|PROD|MODE|BASE_URL|SSR|NODE_OPTIONS|NODE_TLS_REJECT_UNAUTHORIZED|NEXT_RUNTIME|NEXT_OUTPUT|NEXT_TELEMETRY_DISABLED)$'

sources=()
for d in src app lib; do
  if [ -d "$d" ]; then sources+=("$d"); fi
done
for f in next.config.* vite.config.*; do
  if [ -f "$f" ]; then sources+=("$f"); fi
done

scan_sources() {
  grep -rhoE --exclude-dir=node_modules --exclude-dir=__pycache__ --exclude='*.test.*' --exclude='*.spec.*' --exclude='test_*.py' --exclude='conftest.py' \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.py' \
    "process[.]env[.][A-Za-z_][A-Za-z0-9_]*|process[.]env\\[[\"'][A-Za-z_][A-Za-z0-9_]*|import[.]meta[.]env[.][A-Za-z_][A-Za-z0-9_]*|os[.]environ[.]get\\([\"'][A-Za-z_][A-Za-z0-9_]*|os[.]getenv\\([\"'][A-Za-z_][A-Za-z0-9_]*|os[.]environ\\[[\"'][A-Za-z_][A-Za-z0-9_]*" \
    "${sources[@]}" 2> /dev/null | sed -E "s/^.*[.\\[(][\"']?//"
  # Settings modules: zod schema keys (env*.ts) and pydantic settings fields (config*.py, settings*.py).
  # A list or dict field defaulting to an empty literal is computed after load, not read from the environment.
  find "${sources[@]}" -type f \( -name 'env*.ts' -o -name 'env*.js' \) -not -path '*/node_modules/*' -not -name '*.test.*' -exec grep -hoE '^[[:space:]]+[A-Z][A-Z0-9_]*:[[:space:]]*z([.]|$)' {} + 2> /dev/null \
    | sed -E 's/^[[:space:]]+//; s/:.*$//'
  find "${sources[@]}" -type f \( -name 'config*.py' -o -name 'settings*.py' \) -not -name 'test_*' -exec grep -hE '^[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]*:[^=]*=' {} + 2> /dev/null \
    | grep -vE '=[[:space:]]*(\[\]|\{\})[[:space:]]*$' | sed -E 's/^[[:space:]]+//; s/[[:space:]]*:.*$//'
}
: > "$tmp/code.raw"
if [ "${#sources[@]}" -gt 0 ]; then scan_sources > "$tmp/code.raw"; fi
grep -vE "$builtin" "$tmp/code.raw" | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u > "$tmp/code"

grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$example" | sed 's/=$//' | sort -u > "$tmp/active"
grep -oE '^#[[:space:]]*[A-Z][A-Z0-9_]*=' "$example" | sed -E 's/^#[[:space:]]*//; s/=$//' | sort -u > "$tmp/commented"
sort -u "$tmp/active" "$tmp/commented" > "$tmp/documented"

fail=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  echo "check-env-example: the code reads $name but $example does not list it. Add '$name=' (or '# $name=' when it is optional)." >&2
  fail=1
done < <(comm -23 "$tmp/code" "$tmp/documented")
while IFS= read -r name; do
  [ -n "$name" ] || continue
  echo "check-env-example: $example sets $name but no code reads it. Remove the line, or read it in the settings module." >&2
  fail=1
done < <(comm -23 "$tmp/active" "$tmp/code")

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "check-env-example: ok ($(wc -l < "$tmp/code" | tr -d ' ') variables)"

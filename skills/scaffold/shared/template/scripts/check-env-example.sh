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

src_files() {
  find "${sources[@]}" \( -name node_modules -o -name __pycache__ \) -prune -o -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' \) \
    -not -name '*.test.*' -not -name '*.spec.*' -not -name 'test_*.py' -not -name conftest.py -print 2> /dev/null
}

scan_destructured() {
  local f
  while IFS= read -r f; do
    tr '\n' ' ' < "$f" | grep -oE '[{][^{}]*[}][[:space:]]*=[[:space:]]*process[.]env([^A-Za-z0-9_.]|$)' 2> /dev/null \
      | sed -E 's/^[{]//; s/[}].*$//' | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]*[:=].*$//; s/[[:space:]]+$//'
  done < <(src_files)
}

scan_sources() {
  scan_destructured
  grep -rhoE --exclude-dir=node_modules --exclude-dir=__pycache__ --exclude='*.test.*' --exclude='*.spec.*' --exclude='test_*.py' --exclude='conftest.py' \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.py' \
    "process[.]env[?]?[.][A-Za-z_][A-Za-z0-9_]*|process[.]env[?]?\\[[[:space:]]*[\"'][A-Za-z_][A-Za-z0-9_]*|import[.]meta[.]env[?]?[.][A-Za-z_][A-Za-z0-9_]*|os[.]environ[.]get\\([[:space:]]*[\"'][A-Za-z_][A-Za-z0-9_]*|os[.]getenv\\([[:space:]]*[\"'][A-Za-z_][A-Za-z0-9_]*|os[.]environ\\[[[:space:]]*[\"'][A-Za-z_][A-Za-z0-9_]*" \
    "${sources[@]}" 2> /dev/null | sed -E "s/^.*[.\\[(][[:space:]]*[\"']?//"
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

grep -oE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' "$example" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/[[:space:]]*=$//' | sort -u > "$tmp/active"
grep -oE '^#[[:space:]]*(export[[:space:]]+)?[A-Z][A-Z0-9_]*[[:space:]]*=' "$example" | sed -E 's/^#[[:space:]]*(export[[:space:]]+)?//; s/[[:space:]]*=$//' | sort -u > "$tmp/commented"
sort -u "$tmp/active" "$tmp/commented" > "$tmp/documented"

if [ "${#sources[@]}" -gt 0 ]; then
  echo "check-env-example: scanned ${sources[*]}"
else
  echo "check-env-example: no src, app or lib directory found, so no source was scanned."
fi
outside=$(find . -mindepth 1 -maxdepth 3 \( -name node_modules -o -name .git -o -name .venv -o -name __pycache__ -o -name dist -o -name build -o -name .next -o -name .claude -o -name test -o -name tests -o -name docs -o -name scripts \) -prune -o -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' \) -print 2> /dev/null \
  | sed -E 's|^\./||' | grep / | sed -E 's|/.*$||' | sort -u | grep -vxE 'src|app|lib' || true)
if [ -n "$outside" ]; then
  echo "WARNING check-env-example: source exists outside the scanned directories (${outside//$'\n'/, }). Variables read there are not checked; run the check from that project's root." >&2
fi

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

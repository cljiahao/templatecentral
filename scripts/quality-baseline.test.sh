#!/usr/bin/env bash
# Behavioural test for skills/migrate/general/quality-baseline.sh.
# Builds a fixture project in a temp dir and a fake `pnpm` that records its arguments.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/skills/migrate/general/quality-baseline.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/qbtest.XXXXXX") || exit 1
trap '[ -d "$T" ] && rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in output"; fail=1 ;; esac; }
value() { printf '%s\n' "$2" | awk -F'|' -v k="$1" '{ m=$2; gsub(/^ +| +$/, "", m); if (m == k) { v=$3; gsub(/^ +| +$/, "", v); print v } }'; }

mkdir -p "$T/tmp" "$T/bin" "$T/p/src" "$T/p/test" "$T/p/node_modules"
export TMPDIR="$T/tmp"

# usage errors exit 2
bash "$SCRIPT" >/dev/null 2>&1; check "no arguments exits 2" 2 $?
bash "$SCRIPT" "$T/nope" >/dev/null 2>&1; check "missing directory exits 2" 2 $?
bash "$SCRIPT" "$T/p" --label sideways >/dev/null 2>&1; check "bad label exits 2" 2 $?

# fixture: a lint script that would write a marker if anything ran it
cat >"$T/p/package.json" <<JSON
{"name":"fx","scripts":{"lint":"touch $T/MARKER --fix","test":"touch $T/MARKER"},"devDependencies":{"vitest":"1"}}
JSON
printf 'export default [];\n' >"$T/p/eslint.config.mjs"
printf '{}\n' >"$T/p/tsconfig.json"
printf 'a\nb\n\nc\n' >"$T/p/src/a.ts"
printf 'one\ntwo\n' >"$T/p/src/my file.ts"
printf 'test("x", () => {});\nit("y", () => {});\n' >"$T/p/test/a.test.ts"
printf 'node_modules\n' >"$T/p/.gitignore"
(cd "$T/p" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
printf 'untracked\n' >"$T/p/src/u.ts"
printf '// eslint-disable-next-line\nx\n' >"$T/p/src/s.ts"

# fake pnpm: log the arguments, then fail
cat >"$T/bin/pnpm" <<SH
#!/usr/bin/env bash
echo "\$*" >>"$T/pnpm.log"
exit 1
SH
chmod +x "$T/bin/pnpm"

out=$(PATH="$T/bin:$PATH" bash "$SCRIPT" "$T/p" --label before); check "run 1 exits 0" 0 $?
check "source LOC counts spaces in names and untracked files" 9 "$(value 'source LOC' "$out")"
check "test LOC" 2 "$(value 'test LOC' "$out")"
check "static test cases" 2 "$(value 'test cases (static count; a parametrized case counts once)' "$out")"
check "suppressions in code files" 1 "$(value 'suppressions (code files)' "$out")"
contains "label is the column header" "| Metric | before |" "$out"
check "tree unchanged" unchanged "$(value 'project tree after the run' "$out")"
contains "failed lint tool is n/a" "n/a (eslint failed" "$(value 'lint findings' "$out")"
marker=absent; [ -e "$T/MARKER" ] && marker=present
check "no project script ran" absent "$marker"
if grep -qE '^run( |$)' "$T/pnpm.log"; then echo "FAIL pnpm run was called"; fail=1; else echo "ok   pnpm run never called"; fi
contains "eslint called directly" "exec eslint" "$(cat "$T/pnpm.log")"
check "scratch directory removed" 0 "$(find "$T/tmp" -maxdepth 1 -name 'qbaseline.*' | wc -l | tr -d ' ')"

# a file deleted between runs lowers the count
rm "$T/p/src/my file.ts"
out2=$(PATH="$T/bin:$PATH" bash "$SCRIPT" "$T/p" --label after); check "run 2 exits 0" 0 $?
check "deleted file no longer counted" 7 "$(value 'source LOC' "$out2")"
contains "after label" "| Metric | after |" "$out2"

# no pnpm and no node_modules: every tool metric is n/a, static counts still work
rm -rf "$T/p/node_modules"
out3=$(PATH="/usr/bin:/bin" bash "$SCRIPT" "$T/p"); check "run 3 exits 0" 0 $?
contains "missing tools give n/a" "n/a (" "$(value 'line coverage' "$out3")"
check "static counts survive missing tools" 7 "$(value 'source LOC' "$out3")"

exit $fail

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
bash "$SCRIPT" "$T/p" --bogus >/dev/null 2>&1; check "unknown flag exits 2" 2 $?

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

# --static (the default) runs nothing
outs=$(PATH="$T/bin:$PATH" bash "$SCRIPT" "$T/p" --static); check "static run exits 0" 0 $?
pl=absent; [ -e "$T/pnpm.log" ] && pl=present
check "static invokes no tool" absent "$pl"
contains "static says nothing was run" "static mode" "$(value 'lint findings' "$outs")"
check "static counts source LOC" 9 "$(value 'source LOC' "$outs")"

out=$(PATH="$T/bin:$PATH" bash "$SCRIPT" "$T/p" --full --label before); check "run 1 exits 0" 0 $?
check "source LOC counts spaces in names and untracked files" 9 "$(value 'source LOC' "$out")"
check "test LOC" 2 "$(value 'test LOC' "$out")"
check "static test cases" 2 "$(value 'test cases (static count; a parametrized case counts once)' "$out")"
check "suppressions in code files" 1 "$(value 'suppression lines matching (code files)' "$out")"
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
out2=$(PATH="$T/bin:$PATH" bash "$SCRIPT" "$T/p" --full --label after); check "run 2 exits 0" 0 $?
check "deleted file no longer counted" 7 "$(value 'source LOC' "$out2")"
contains "after label" "| Metric | after |" "$out2"

# no pnpm and no node_modules: every tool metric is n/a, static counts still work
rm -rf "$T/p/node_modules"
out3=$(PATH="/usr/bin:/bin" bash "$SCRIPT" "$T/p" --full); check "run 3 exits 0" 0 $?
contains "missing tools give n/a" "n/a (" "$(value 'line coverage' "$out3")"
check "static counts survive missing tools" 7 "$(value 'source LOC' "$out3")"

# --- Python fixture with fake tools: they log their arguments, so the test can see what ran
mkdir -p "$T/py/src" "$T/py/tests" "$T/fbin"
printf '[tool.pyright]\n' >"$T/py/pyproject.toml"
printf 'def f():\n    return 1\n' >"$T/py/src/a.py"
printf 'def test_f():\n    assert 1\n' >"$T/py/tests/test_a.py"
printf 'SECRET=1\n' >"$T/py/.env"; printf '//reg\n' >"$T/py/.npmrc"; printf 'k\n' >"$T/py/key.pem"
(cd "$T/py" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
cat >"$T/fbin/ruff" <<SH
#!/usr/bin/env bash
echo "ruff \$*" >>"$T/tools.log"
case "\$1" in --version) echo "ruff 0.0.0"; exit 0 ;; esac
case " \$* " in *" --isolated "*) ls -A >"$T/cc.list"; echo '[]' >"$T/c901.out"; exit 0 ;; esac
[ -n "\${FAKE_WRITE:-}" ] && echo x >stray.txt
[ -n "\${FAKE_EDIT:-}" ] && echo '# edited' >>src/a.py
[ -n "\${FAKE_IGN:-}" ] && echo x >ignored.log
if [ -n "\${FAKE_SLEEP:-}" ]; then echo \$\$ >"$T/ruff.pid"; sleep 30 & echo \$! >"$T/sleep.pid"; wait; fi
out=; while [ \$# -gt 0 ]; do [ "\$1" = -o ] && out=\$2; shift; done
[ -n "\$out" ] && echo '[]' >"\$out"
exit 0
SH
cat >"$T/fbin/pyright" <<SH
#!/usr/bin/env bash
echo "pyright \$*" >>"$T/tools.log"
echo "warning on stderr" >&2
echo '{"summary":{"errorCount":0}}'
SH
cat >"$T/fbin/python" <<SH
#!/usr/bin/env bash
case "\$1" in
  -c) [ -n "\${FAKE_NOCOV:-}" ] && case "\$2" in *pytest_cov*) exit 1 ;; esac; exit 0 ;;
  -m) echo "python \$*" >>"$T/tools.log"; exit 0 ;;
esac
SH
chmod +x "$T/fbin/ruff" "$T/fbin/pyright" "$T/fbin/python"
PYPATH="$T/fbin:/usr/bin:/bin"

: >"$T/tools.log"
PATH="$PYPATH" bash "$SCRIPT" "$T/py" --static >/dev/null
check "static python run invokes no tool" 0 "$(wc -l <"$T/tools.log" | tr -d ' ')"

outp=$(PATH="$PYPATH" bash "$SCRIPT" "$T/py" --full); check "python full run exits 0" 0 $?
contains "pytest gets --cov with its report" "--cov=src --cov-report=xml:" "$(grep 'python -m pytest' "$T/tools.log")"
contains "ruff runs without a cache" "check --no-cache" "$(grep '^ruff check --no-cache' "$T/tools.log" | head -1)"
check "pyright stderr stays out of the json report" 0 "$(value 'type errors' "$outp")"
check "python tree unchanged" unchanged "$(value 'project tree after the run' "$outp")"
check "scratch copy holds only code, no secrets or config" "src tests" "$(tr '\n' ' ' <"$T/cc.list" | sed 's/ $//')"

: >"$T/tools.log"
FAKE_NOCOV=1 PATH="$PYPATH" bash "$SCRIPT" "$T/py" --full >/dev/null
if grep 'python -m pytest' "$T/tools.log" | grep -q -- '--cov'; then echo "FAIL --cov-report or --cov passed without pytest-cov"; fail=1; else echo "ok   no --cov flags without pytest-cov"; fi

# a tool that writes into the project is reported
outw=$(FAKE_WRITE=1 PATH="$PYPATH" bash "$SCRIPT" "$T/py" --full)
contains "a written file makes the tree check say CHANGED" "CHANGED" "$(value 'project tree after the run' "$outw")"
contains "the written file is named" "stray.txt" "$(value 'project tree after the run' "$outw")"
rm -f "$T/py/stray.txt" "$T/ng/stray.txt"

# timeout path
outt=$(FAKE_SLEEP=1 QB_RUN_LIMIT=1 PATH="$PYPATH" bash "$SCRIPT" "$T/py" --full)
contains "a timed-out tool reports exit 124" "124" "$(value 'lint findings' "$outt")"

# a tracked file edited by a tool is detected, an ignored file is classified apart
oute=$(FAKE_EDIT=1 PATH="$PYPATH" bash "$SCRIPT" "$T/py" --full)
contains "an edited tracked file makes the tree CHANGED" "CHANGED" "$(value 'project tree after the run' "$oute")"
contains "the edited tracked file is named" "src/a.py" "$(value 'project tree after the run' "$oute")"
(cd "$T/py" && git checkout -q -- src/a.py)
printf 'ignored.log\n' >"$T/py/.gitignore"
outi=$(FAKE_IGN=1 PATH="$PYPATH" bash "$SCRIPT" "$T/py" --full)
contains "an ignored file is reported apart" "unchanged in git; the run wrote ignored files: ignored.log" "$(value 'project tree after the run' "$outi")"
rm -f "$T/py/ignored.log" "$T/py/.gitignore"

# INT and TERM: the tool's whole process group dies and the scratch directory goes
rm -f "$T/ruff.pid" "$T/sleep.pid"
FAKE_SLEEP=1 PATH="$PYPATH" bash "$SCRIPT" "$T/py" --full >/dev/null 2>&1 &
spid=$!
n=0; while [ ! -s "$T/sleep.pid" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -TERM "$spid"; wait "$spid" 2>/dev/null; check "TERM exits 143" 143 $?
alive() { kill -0 "$(cat "$1")" 2>/dev/null && echo alive || echo dead; }
n=0; while [ "$(alive "$T/sleep.pid")" = alive ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
check "TERM kills the tool" dead "$(alive "$T/ruff.pid")"
check "TERM kills the tool's child" dead "$(alive "$T/sleep.pid")"
check "TERM removes the scratch directory" 0 "$(find "$T/tmp" -maxdepth 1 -name 'qbaseline.*' | wc -l | tr -d ' ')"

# a project that is not a git repository
cp -R "$T/py" "$T/ng" && rm -rf "$T/ng/.git"
outn=$(PATH="$PYPATH" bash "$SCRIPT" "$T/ng" --static); check "non-git static exits 0" 0 $?
check "non-git source LOC" 2 "$(value 'source LOC' "$outn")"
check "non-git tree unchanged" unchanged "$(value 'project tree after the run' "$outn")"
outn=$(FAKE_WRITE=1 PATH="$PYPATH" bash "$SCRIPT" "$T/ng" --full)
contains "non-git full run is checked too" "CHANGED" "$(value 'project tree after the run' "$outn")"

# --- TypeScript success path: a fake pnpm that answers eslint, tsc, vitest, jscpd and the scratch install
mkdir -p "$T/bin2" "$T/p/node_modules"
cat >"$T/bin2/pnpm" <<SH
#!/usr/bin/env bash
echo "pnpm \$* ENV=\${FAKE_ENV_MARK:-}" >>"$T/pnpm2.log"
[ "\$1" = add ] && exit 0
case " \$* " in *" --showConfig "*) echo '{"compilerOptions":{"composite": true}}'; exit 0 ;; esac
out=; od=; rd=; while [ \$# -gt 0 ]; do
  case "\$1" in -o) out=\$2 ;; --outputFile=*) out=\${1#*=} ;; --output) od=\$2 ;; --coverage.reportsDirectory=*) rd=\${1#*=} ;; esac
  shift
done
case " \$* \$out" in *vitest*) :;; esac
if [ -n "\$rd" ]; then mkdir -p "\$rd"; echo '<coverage line-rate="0.85"></coverage>' >"\$rd/cobertura-coverage.xml"; fi
if [ -n "\$od" ]; then mkdir -p "\$od"; echo '{"statistics":{"total":{"percentage":1.5}}}' >"\$od/jscpd-report.json"; fi
if [ -n "\$out" ]; then
  case "\$out" in *vitest.json) echo '{"numFailedTests":0,"numTotalTests":3}' >"\$out" ;; *) echo '[]' >"\$out" ;; esac
fi
exit 0
SH
chmod +x "$T/bin2/pnpm"
mkdir -p "$T/keep"
outs=$(FAKE_ENV_MARK=passed PATH="$T/bin2:/usr/bin:/bin" bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/keep/cov"); check "ts success run exits 0" 0 $?
check "ts lint findings" 0 "$(value 'lint findings' "$outs")"
check "ts type errors" 0 "$(value 'type errors' "$outs")"
check "ts tests" "0 failed of 3" "$(value 'tests failed' "$outs")"
check "ts coverage" "85.0%" "$(value 'line coverage' "$outs")"
check "ts complexity" 0 "$(value 'complexity over 15' "$outs")"
check "ts duplication" "1.5%" "$(value 'duplication' "$outs")"
check "ts tree unchanged" unchanged "$(value 'project tree after the run' "$outs")"
contains "composite tsconfig points build info into scratch" "--tsBuildInfoFile" "$(grep 'exec tsc --noEmit' "$T/pnpm2.log")"
contains "environment reaches the tool" "ENV=passed" "$(grep 'exec eslint' "$T/pnpm2.log" | head -1)"
check "kept coverage xml exists" yes "$([ -f "$T/keep/cov/cobertura.xml" ] && echo yes || echo no)"
check "kept coverage row" "$(cd "$T/keep" && pwd -P)/cov/cobertura.xml" "$(value 'coverage xml kept' "$outs")"

# --keep-coverage validation
bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/p/cov" >/dev/null 2>&1; check "keep dir inside project exits 2" 2 $?
bash "$SCRIPT" "$T/p" --static --keep-coverage "$T/keep/x" >/dev/null 2>&1; check "keep without --full exits 2" 2 $?
bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/missing/x" >/dev/null 2>&1; check "keep with missing parent exits 2" 2 $?
check "nothing created inside the project" no "$([ -e "$T/p/cov" ] && echo yes || echo no)"
ln -s "$T/p" "$T/lnk"
bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/lnk" >/dev/null 2>&1; check "keep symlink to the project exits 2" 2 $?
bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/lnk/cov" >/dev/null 2>&1; check "keep under a symlink into the project exits 2" 2 $?
if [ -d "$T/P" ]; then
  bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/P/cov" >/dev/null 2>&1; check "keep with a case-variant project path exits 2" 2 $?
  bash "$SCRIPT" "$T/P" --full --keep-coverage "$T/p/cov" >/dev/null 2>&1; check "case-variant project with keep inside exits 2" 2 $?
else echo "skip case-variant keep-coverage tests: the filesystem is case-sensitive"; fi
mkdir -p "$T/keep2"; echo victim >"$T/victim"; ln -s "$T/victim" "$T/keep2/cobertura.xml"
outl=$(PATH="$T/bin2:/usr/bin:/bin" bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/keep2")
contains "a symlinked cobertura.xml is not written through" "is a symlink" "$(value 'coverage xml kept' "$outl")"
check "the symlink target is untouched" victim "$(cat "$T/victim")"
check "a refused write leaves no temporary file" 0 "$(find "$T/keep2" -name '.cobertura.*' | wc -l | tr -d ' ')"
outk=$(PATH="$T/bin2:/usr/bin:/bin" bash "$SCRIPT" "$T/p" --full --keep-coverage "$T/keep")
check "a rerun overwrites the kept file" "$(cd "$T/keep" && pwd -P)/cobertura.xml" "$(value 'coverage xml kept' "$outk")"
check "a successful write leaves no temporary file" 0 "$(find "$T/keep" -name '.cobertura.*' | wc -l | tr -d ' ')"

exit $fail

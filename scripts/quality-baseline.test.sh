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
contains "failed lint tool is n/a" "n/a (failed: eslint failed" "$(value 'lint findings' "$out")"
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

# --- --compare: a verdict table, exit 1 when any measured number got worse, 2 on a table it cannot trust
mkdir -p "$T/g" && (cd "$T/g" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m one && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m two)
H1=$(git -C "$T/g" rev-parse HEAD~1); H2=$(git -C "$T/g" rev-parse HEAD)
export QB_REPO="$T/g"
TBL_MODE=full TBL_HEAD=$H1 TBL_TREE=clean TBL_TESTS='0 failed of 3' TBL_THR=1
tbl() { # tbl <label> <lint> <types> <cov> <cplx> <dup> <supp> <excl>
  printf '| Metric | %s |\n|---|---|\n| lint findings | %s |\n| type errors | %s |\n| tests failed | '"$TBL_TESTS"' |\n| line coverage | %s |\n| complexity over 15 | %s |\n| duplication | %s |\n| suppression lines matching (code files) | %s |\n| coverage, lint and Sonar exclusions | %s |\n| coverage thresholds configured | '"$TBL_THR"' |\n| mode | %s |\n| git head | %s |\n| git tree | %s |\n' "$@" "$TBL_MODE" "$TBL_HEAD" "$TBL_TREE"
}
tbl before 4 2 80.0% 3 1.5% 2 1 >"$T/b.md"
TBL_TREE=dirty tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/same.md"
TBL_TREE=dirty tbl after 1 0 90.5% "2 (cyclomatic proxy)" 1.0% 0 0 >"$T/better.md"
outc=$(bash "$SCRIPT" --compare "$T/b.md" "$T/same.md"); check "compare equal exits 0" 0 $?
contains "compare equal says OK" "OK: no measured number got worse" "$outc"
contains "compare prints both commits" "commits: before ${H1:0:9} (clean), after ${H1:0:9} (dirty)" "$outc"
outc=$(bash "$SCRIPT" --compare "$T/b.md" "$T/better.md"); check "compare improved exits 0" 0 $?
contains "compare names an improvement" "improved" "$outc"
regress() { # regress <name> <lint> <types> <cov> <cplx> <dup> <supp> <excl>
  local n=$1; shift
  TBL_TREE=dirty tbl after "$@" >"$T/r.md"
  outc=$(bash "$SCRIPT" --compare "$T/b.md" "$T/r.md"); check "compare fails on worse $n" 1 $?
  contains "compare table marks $n WORSE" "WORSE" "$outc"
}
regress "lint findings" 5 2 80.0% 3 1.5% 2 1
regress "type errors" 4 3 80.0% 3 1.5% 2 1
regress "coverage" 4 2 79.9% 3 1.5% 2 1
regress "complexity" 4 2 80.0% 4 1.5% 2 1
regress "duplication" 4 2 80.0% 3 1.6% 2 1
regress "suppressions" 4 2 80.0% 3 1.5% 3 1
regress "exclusions" 4 2 80.0% 3 1.5% 2 2
TBL_TREE=dirty tbl after 4 2 "n/a (failed: no coverage report)" 3 1.5% 2 1 >"$T/r.md"
outc=$(bash "$SCRIPT" --compare "$T/b.md" "$T/r.md"); check "a number no longer measured fails" 1 $?
contains "not measured after is named" "not measured after" "$outc"
# a tool absent before and present after is newly measured, not silently skipped
tbl before "n/a (no eslint.config.*)" "n/a (no tsconfig.json)" "n/a (no vitest or jest in package.json)" "n/a (ruff not installed)" "n/a (no pnpm or npx)" 2 1 >"$T/nb.md"
outc=$(bash "$SCRIPT" --compare "$T/nb.md" "$T/better.md"); check "numbers absent before are allowed" 0 $?
contains "newly measured rows carry the value" "newly measured (90.5%)" "$outc"
# n/a before for any other reason is not a baseline
for failed in "n/a (failed: eslint failed, exit 2)" "n/a (eslint failed, exit 2)" "n/a (no test report, exit 1)" "n/a (no coverage report; is a coverage provider installed?)" "n/a (timeout)" "n/a (static mode: nothing was run)" "n/a (not installed anywhere)"; do
  tbl before 4 2 "$failed" 3 1.5% 2 1 >"$T/failed.md"
  bash "$SCRIPT" --compare "$T/failed.md" "$T/better.md" >/dev/null 2>&1; check "a failure string before is not an absent tool: $failed" 2 $?
done
for absent in "n/a (no pnpm)" "n/a (dependencies not installed: no node_modules)" "n/a (no eslint.config.*)" "n/a (no tsconfig.json)" "n/a (no vitest or jest in package.json)" "n/a (ruff not installed)" "n/a (no configured type checker on PATH or in .venv)" "n/a (no python)" "n/a (pytest not installed)" "n/a (pytest-cov not installed)" "n/a (no src, app or lib directory)" "n/a (no pnpm or npx)" "n/a (no package.json, pyproject.toml or requirements file)"; do
  tbl before 4 2 "$absent" 3 1.5% 2 1 >"$T/absent.md"
  bash "$SCRIPT" --compare "$T/absent.md" "$T/better.md" >/dev/null 2>&1; check "an absent tool before is accepted: $absent" 0 $?
done
check "no failure string in the script reads like an absent tool" 0 "$(grep -v 'KEPT=' "$SCRIPT" | grep -cE 'n/a \((no test report|no coverage report|eslint failed|tsc failed|timeout|jscpd failed|pyright failed|complexity run failed)')"
# a static before table cannot be a baseline
TBL_MODE=static tbl before "n/a (static mode: nothing was run)" "n/a (static mode: nothing was run)" "n/a (static mode: nothing was run)" "n/a (static mode: nothing was run)" "n/a (static mode: nothing was run)" 2 1 >"$T/static.md"
TBL_TREE=dirty tbl after 99 99 1.0% 99 50% 9 9 >"$T/bad.md"
bash "$SCRIPT" --compare "$T/static.md" "$T/bad.md" >/dev/null 2>&1; check "a static before table exits 2, not 0" 2 $?
TBL_MODE=static TBL_TREE=dirty tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/staticafter.md"
bash "$SCRIPT" --compare "$T/b.md" "$T/staticafter.md" >/dev/null 2>&1; check "a static after table exits 2" 2 $?
# malformed numbers are not a pass
for bad in "1.5e0%" "1.5.2%" ".5%" "NaN" "-1"; do
  TBL_TREE=dirty tbl after 4 2 80.0% 3 "$bad" 2 1 >"$T/r.md"
  bash "$SCRIPT" --compare "$T/b.md" "$T/r.md" >/dev/null 2>&1; check "malformed duplication [$bad] exits 2" 2 $?
done
# duplicate metric rows are not a way to pick a number
{ cat "$T/same.md"; printf '| lint findings | 0 |\n'; } >"$T/dupafter.md"
bash "$SCRIPT" --compare "$T/b.md" "$T/dupafter.md" >/dev/null 2>&1; check "a duplicate metric row after exits 2" 2 $?
{ cat "$T/b.md"; printf '| lint findings | 99 |\n'; } >"$T/dupbefore.md"
bash "$SCRIPT" --compare "$T/dupbefore.md" "$T/same.md" >/dev/null 2>&1; check "a duplicate metric row before exits 2" 2 $?
# the test total may not fall, and a rise in failures or a fall in thresholds is worse
TBL_TESTS='0 failed of 10' tbl before 4 2 80.0% 3 1.5% 2 1 >"$T/t10.md"
TBL_TREE=dirty TBL_TESTS='0 failed of 0' tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/t0.md"
outc=$(bash "$SCRIPT" --compare "$T/t10.md" "$T/t0.md"); check "a fallen test total exits 1" 1 $?
contains "a fallen test total prints both totals" "test total fell 10 to 0" "$outc"
contains "a fallen test total names who records a consolidation" "retaking the baseline" "$outc"
TBL_TREE=dirty TBL_TESTS='0 failed of 12' tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/t12.md"
bash "$SCRIPT" --compare "$T/t10.md" "$T/t12.md" >/dev/null 2>&1; check "a larger test total passes" 0 $?
TBL_TREE=dirty TBL_TESTS='1 failed of 3' tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/tf.md"
bash "$SCRIPT" --compare "$T/b.md" "$T/tf.md" >/dev/null 2>&1; check "a rise in failed tests exits 1" 1 $?
TBL_TREE=dirty TBL_THR=0 tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/thr.md"
bash "$SCRIPT" --compare "$T/b.md" "$T/thr.md" >/dev/null 2>&1; check "a fall in configured thresholds exits 1" 1 $?
# the tie to a commit
TBL_TREE=clean tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/r.md"
bash "$SCRIPT" --compare "$T/b.md" "$T/r.md" >/dev/null 2>&1; check "one commit, both trees clean exits 2" 2 $?
TBL_HEAD=$H2 TBL_TREE=clean tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/r.md"
bash "$SCRIPT" --compare "$T/b.md" "$T/r.md" >/dev/null 2>&1; check "a later commit is accepted" 0 $?
TBL_HEAD=$H2 TBL_TREE=clean tbl before 4 2 80.0% 3 1.5% 2 1 >"$T/b2.md"
TBL_HEAD=$H1 TBL_TREE=clean tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/r.md"
bash "$SCRIPT" --compare "$T/b2.md" "$T/r.md" >/dev/null 2>&1; check "a before commit that is not an ancestor exits 2" 2 $?
TBL_HEAD="no git" TBL_TREE="no git" tbl before 4 2 80.0% 3 1.5% 2 1 >"$T/ng.md"
TBL_HEAD="no git" TBL_TREE="no git" tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/ng2.md"
mkdir -p "$T/nogit"
outc=$(QB_REPO="$T/nogit" bash "$SCRIPT" --compare "$T/ng.md" "$T/ng2.md"); check "outside a repository the comparison still runs" 0 $?
contains "outside a repository is stated" "no git" "$outc"
bash "$SCRIPT" --compare "$T/ng.md" "$T/ng2.md" >/dev/null 2>&1; check "a no git table inside a repository exits 2" 2 $?
bash "$SCRIPT" --compare "$T/b.md" "$T/ng2.md" >/dev/null 2>&1; check "one no git table inside a repository exits 2" 2 $?
TBL_HEAD=0123456789012345678901234567890123456789 TBL_TREE=clean tbl after 4 2 80.0% 3 1.5% 2 1 >"$T/unk.md"
unkout=$(bash "$SCRIPT" --compare "$T/b.md" "$T/unk.md" 2>&1 >/dev/null); check "an unresolvable after commit exits 2" 2 $?
contains "an unresolvable commit is named" "is not in" "$unkout"
TBL_TREE=dirty
printf '| Metric | before |\n|---|---|\n| lint findings | n/a (no eslint.config.*) |\n| mode | full |\n| git head | no git |\n| git tree | no git |\n' >"$T/none.md"
QB_REPO="$T/nogit" bash "$SCRIPT" --compare "$T/none.md" "$T/none.md" >/dev/null 2>&1; check "a table missing its metric rows exits 2" 2 $?
bash "$SCRIPT" --compare "$T/b.md" >/dev/null 2>&1; check "one single-column file exits 2" 2 $?
outc=$(bash "$SCRIPT" --compare "$T/b.md" "$T/better.md")
printf '%s\n' "$outc" | sed '/^$/,$d' >"$T/rec.md"
bash "$SCRIPT" --compare "$T/rec.md" >/dev/null 2>&1; check "a saved compare table re-compares before with after, ignoring the verdict column" 0 $?
bash "$SCRIPT" --compare "$T/b.md" "$T/nope.md" >/dev/null 2>&1; check "compare with a missing file exits 2" 2 $?
bash "$SCRIPT" --compare >/dev/null 2>&1; check "compare without files exits 2" 2 $?

# the table records the commit and tree state, and the wider suppression and exclusion forms are counted
gp="$T/gp"; mkdir -p "$gp/src"; printf 'const a = 1;\n' >"$gp/src/a.ts"; printf '{}\n' >"$gp/tsconfig.json"; printf '{"name":"g"}\n' >"$gp/package.json"
(cd "$gp" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
outc=$(bash "$SCRIPT" "$gp" --static)
check "table records the head" "$(git -C "$gp" rev-parse HEAD)" "$(value "git head" "$outc")"
check "table records a clean tree" "clean" "$(value "git tree" "$outc")"
printf 'x\n' >"$gp/src/u.ts"
outc=$(bash "$SCRIPT" "$gp" --static); check "table records a dirty tree" "dirty" "$(value "git tree" "$outc")"
rm -f "$gp/src/u.ts"
base_supp=$(value "suppression lines matching (code files)" "$(bash "$SCRIPT" "$gp" --static)")
for form in '# pylint: disable=x' '// biome-ignore lint: x' '# nosec' '# pragma: no cover' '# pragma: no branch' '/* v8 ignore next */' '/* istanbul ignore next */' '// @ts-expect-error' '// @ts-nocheck' '# type: ignore' '# noqa' '// NOSONAR' '@SuppressWarnings("x")' '# type:ignore' '# NOQA' '/* istanbul  ignore next */'; do
  printf 'x = 1 %s\n' "$form" >"$gp/src/s.ts"
  now=$(value "suppression lines matching (code files)" "$(bash "$SCRIPT" "$gp" --static)")
  check "suppression form counted: $form" "$((base_supp + 1))" "$now"
done
printf 'x = 1  # noqa  # type: ignore\n' >"$gp/src/s.ts"
check "two suppressions on one line count twice" "$((base_supp + 2))" "$(value "suppression lines matching (code files)" "$(bash "$SCRIPT" "$gp" --static)")"
rm -f "$gp/src/s.ts"; mkdir -p "$gp/vendor"; printf 'x = 1  # noqa\n' >"$gp/vendor/v.ts"
check "a vendor directory is not counted" "$base_supp" "$(value "suppression lines matching (code files)" "$(bash "$SCRIPT" "$gp" --static)")"
rm -rf "$gp/vendor"
base_excl=$(value "coverage, lint and Sonar exclusions" "$(bash "$SCRIPT" "$gp" --static)")
excl_form() { # excl_form <file> <line>
  printf '%s\n' "$2" >"$gp/$1"
  now=$(value "coverage, lint and Sonar exclusions" "$(bash "$SCRIPT" "$gp" --static)")
  check "exclusion form counted: $1 $2" "$((base_excl + 1))" "$now"
  rm -f "$gp/$1"
}
excl_form sonar-project.properties 'sonar.exclusions=src/**'
excl_form sonar-project.properties 'sonar.coverage.exclusions=src/**'
excl_form vitest.config.ts '    exclude: ["src/**"],'
excl_form .coveragerc 'omit = src/*'
excl_form .eslintignore 'src/legacy'
excl_form eslint.config.mjs 'ignorePatterns: ["src"]'
excl_form .jscpd.json '"ignore": ["src"]'
excl_form ruff.toml 'extend-exclude = ["src"]'
excl_form ruff.toml 'per-file-ignores = {}'
excl_form vitest.config.ts 'export default { test: { coverage: { exclude: ["src"] } } };'
excl_form eslint.config.mjs 'export default [{ ignores: ["src"] }];'
excl_form ruff.toml 'ignore = ["E501"]'
excl_form pyproject.toml 'ignore_errors = true'
excl_form pytest.ini 'addopts = --ignore=tests/slow'
excl_form sonar-project.properties 'sonar.issue.ignore.multicriteria=e1'
excl_form eslint.config.mjs "export default [{ rules: { 'no-undef': 'off' } }];"
excl_form eslint.config.mjs "export default [{ rules: { 'no-undef': 0 } }];"

exit $fail

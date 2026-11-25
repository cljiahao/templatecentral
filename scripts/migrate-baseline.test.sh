#!/usr/bin/env bash
# Behavioural test for skills/migrate/general/gate-baseline.sh and the bare --baseline of harness-refresh.sh.
# Each behaviour has a clean control and a case that fails when the behaviour is reverted. No network; the tools are stubs.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G="$ROOT/skills/migrate/general/gate-baseline.sh"
REFRESH="$ROOT/skills/migrate/general/harness-refresh.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/gbtest.XXXXXX") || exit 1
trap '[ -d "$T" ] && rm -rf "${T:?}"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in output: $3"; fail=1 ;; esac; }
absent() { case "$3" in *"$2"*) echo "FAIL $1: [$2] found in output"; fail=1 ;; *) echo "ok   $1" ;; esac; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1"; else sha256sum -- "$1"; fi | cut -d' ' -f1; }
treehash() { (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then printf '%s L %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(sha "$f")"; fi; done | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1); }
gitc() { git -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t "$@"; }

# gb <dir> <args...>: run the helper on a project dir; stdin is the gate output.
gb() { local d=$1; shift; bash "$G" -C "$d" "$@" 2>&1; }
newproj() { mkdir -p "$T/$1"; echo "$T/$1"; }
BL=.claude/gate-baseline.txt
tab=$(printf '\t')
HEADER_LINE='# templatecentral gate baseline v2'
# nent <file>: the number of entry lines (gate lines excluded).
nent() { tail -n +2 "$1" | grep -vc '^# gate'; }

OLD='src/a.ts:3:1: Unexpected any [Error/no-any]
src/a.ts:9:5: Unused variable x [Error/no-unused]
src/b.ts:1:1: Missing return type [Error/types]'

# record, and a rerun that changes nothing
P=$(newproj rec)
out=$(printf '%s\n\n3 problems\n' "$OLD" | gb "$P" record lint colon); check "record exits 0" 0 $?
contains "record counts findings" "recorded 3 finding(s) in 3 entr" "$out"
h1=$(sha "$P/$BL")
check "file starts with the header" "# templatecentral gate baseline v2" "$(head -n 1 "$P/$BL")"
contains "entry names gate, file, count, fingerprint" "lint${tab}src/a.ts${tab}1${tab}Unexpected any [Error/no-any]" "$(cat "$P/$BL")"
absent "no line number in the file" ":3:1" "$(cat "$P/$BL")"
out=$(printf '%s\n' "$OLD" | gb "$P" record lint colon); check "rerun exits 0" 0 $?
contains "rerun says unchanged" "unchanged" "$out"
check "rerun leaves the file byte-identical" "$h1" "$(sha "$P/$BL")"
out=$(gb "$P" validate); check "validate passes on a recorded file" 0 $?
check "gate line names the tool" "# gate${tab}lint${tab}colon" "$(sed -n 2p "$P/$BL")"
check "entries sorted" "$(tail -n +2 "$P/$BL")" "$(tail -n +2 "$P/$BL" | LC_ALL=C sort -t "$tab" -k1,1 -k2,2 -k4)"

# the gate: old findings pass, a new one fails
out=$(printf '%s\n' "$OLD" | gb "$P" check lint colon); check "control: only old findings pass" 0 $?
contains "control says ok" "lint ok (no new finding)" "$out"
out=$(printf '%s\nsrc/c.ts:4:2: Unexpected any [Error/no-any]\n' "$OLD" | gb "$P" check lint colon); check "a new violation fails" 1 $?
contains "new violation is named" "NEW lint: src/c.ts: Unexpected any [Error/no-any]" "$out"
out=$(printf '%s\nsrc/a.ts:12:1: Another message [Error/other]\n' "$OLD" | gb "$P" check lint colon); check "a new rule in an old file fails" 1 $?

# line numbers do not matter; a repeated finding counts as one more
MOVED='src/a.ts:103:1: Unexpected any [Error/no-any]
src/a.ts:109:5: Unused variable x [Error/no-unused]
src/b.ts:51:1: Missing return type [Error/types]'
out=$(printf '%s\n' "$MOVED" | gb "$P" check lint colon); check "moved old violations pass" 0 $?
out=$(printf '%s\nsrc/a.ts:40:1: Unexpected any [Error/no-any]\n' "$OLD" | gb "$P" check lint colon); check "a second copy fails" 1 $?
contains "second copy reports counts" "found 2, baseline 1" "$out"
out=$(printf '%s\n' "$OLD" | sed 's#src/b.ts#src/renamed.ts#' | gb "$P" check lint colon); check "a renamed file counts as new" 1 $?

# a fixed violation is reported removable, never silently kept
out=$(printf '%s\n' "$OLD" | sed '/Missing return/d' | gb "$P" check lint colon); check "a fixed violation still passes" 0 $?
contains "fixed violation is removable" "REMOVABLE lint: src/b.ts: Missing return type" "$out"
absent "control: nothing removable when all still present" "REMOVABLE" "$(printf '%s\n' "$OLD" | gb "$P" check lint colon)"
out=$(printf '%s\n' "$OLD" | sed '/Missing return/d' | gb "$P" check lint colon --strict-stale); check "--strict-stale fails on removable" 1 $?

# prune shrinks and never adds
cp "$P/$BL" "$T/before-prune.txt"
FIXED=$(printf '%s\n' "$OLD" | sed '/Missing return/d')
out=$(printf '%s\nsrc/new.ts:1:1: Brand new [Error/new]\n' "$FIXED" | gb "$P" prune lint colon); check "prune exits 0" 0 $?
contains "prune reports" "1 entr(ies) removed" "$out"
check "prune removed the fixed entry" 2 "$(nent "$P/$BL")"
absent "prune did not add the new finding" "Brand new" "$(cat "$P/$BL")"
out=$(printf '%s\n' "$OLD" | gb "$P" check lint colon); check "after prune the removed finding is new again" 1 $?
cp "$T/before-prune.txt" "$P/$BL"
printf '%s\nsrc/a.ts:40:1: Unexpected any [Error/no-any]\n' "$OLD" | gb "$P" prune lint colon >/dev/null
contains "prune never raises a count" "lint${tab}src/a.ts${tab}1${tab}Unexpected any" "$(cat "$P/$BL")"

# growth is refused unless a human waives it
G1=$(newproj grow)
(cd "$G1" && git init -q -b main) >/dev/null 2>&1
commit() { (cd "$G1" && git add -A && gitc commit -qm "$1"); }
printf '%s\n' "$OLD" | gb "$G1" record lint colon >/dev/null
commit base
out=$(gb "$G1" growth HEAD); check "control: no change is not growth" 0 $?
printf '%s\n' "$FIXED" | gb "$G1" prune lint colon >/dev/null; commit shrink
out=$(gb "$G1" growth HEAD~1); check "control: a shrink is not growth" 0 $?
printf 'src/c.ts:1:1: Added [Error/added]\n' | gb "$G1" record types colon >/dev/null
commit "new gate"
out=$(gb "$G1" growth HEAD~1); check "a new entry fails" 1 $?
contains "growth line uses the ratchet format" "WEAKENED .claude/gate-baseline.txt: the baseline grew: types src/c.ts" "$out"
sed "s/^lint${tab}src\/a.ts${tab}1${tab}Unexpected/lint${tab}src\/a.ts${tab}2${tab}Unexpected/" "$G1/$BL" >"$T/raised.txt" && cp "$T/raised.txt" "$G1/$BL"
commit raise
out=$(gb "$G1" growth HEAD~1); check "a raised count fails" 1 $?
contains "raised count names both numbers" "(1 -> 2)" "$out"
G2=$(newproj intro)
(cd "$G2" && git init -q -b main && echo x >f && git add -A && gitc commit -qm base) >/dev/null 2>&1
printf '%s\n' "$OLD" | gb "$G2" record lint colon >/dev/null
(cd "$G2" && git add -A && gitc commit -qm intro)
out=$(gb "$G2" growth HEAD~1); check "introducing the file is growth" 1 $?
contains "introduction is explained" "new in this change" "$out"
printf 'garbage\n' >"$G2/$BL"; (cd "$G2" && git add -A && gitc commit -qm bad)
out=$(gb "$G2" growth HEAD~1); check "an unreadable head file exits 2" 2 $?
contains "unreadable line is in the ratchet format" "UNREADABLE .claude/gate-baseline.txt" "$out"

# a missing or corrupt file fails closed
M=$(newproj missing)
out=$(printf '%s\n' "$OLD" | gb "$M" check lint colon); check "missing file fails" 2 $?
contains "missing file is named" "is missing" "$out"
C=$(newproj corrupt)
printf '%s\n' "$OLD" | gb "$C" record lint colon >/dev/null
printf '%s\n' "$OLD" | gb "$C" check lint colon >/dev/null; check "control: intact file passes" 0 $?
cp "$C/$BL" "$T/good.txt"
# corrupt <shell command>: restore the good file, damage it with the command, run a check, print its exit code.
corrupt() { rm -f "${C:?}/${BL:?}"; cp "$T/good.txt" "$C/$BL"; sh -c "$1"; printf '%s\n' "$OLD" | gb "$C" check lint colon >/dev/null; echo $?; }
check "unsorted file fails" 2 "$(corrupt "{ head -n 1 '$T/good.txt'; tail -n +2 '$T/good.txt' | sort -r; } >'$C/$BL'")"
check "duplicate entry fails" 2 "$(corrupt "{ cat '$T/good.txt'; tail -n 1 '$T/good.txt'; } >'$C/$BL'")"
check "bad count fails" 2 "$(corrupt "sed 's/${tab}1${tab}/${tab}x${tab}/' '$T/good.txt' >'$C/$BL'")"
check "zero count fails" 2 "$(corrupt "sed 's/${tab}1${tab}/${tab}0${tab}/' '$T/good.txt' >'$C/$BL'")"
check "missing header fails" 2 "$(corrupt "tail -n +2 '$T/good.txt' >'$C/$BL'")"
check "short line fails" 2 "$(corrupt "printf 'lint${tab}x\\n' >>'$C/$BL'")"
check "no final newline fails" 2 "$(corrupt "printf '%s' \"\$(cat '$T/good.txt')\" >'$C/$BL'")"
check "symlinked file fails" 2 "$(corrupt "rm '$C/$BL'; ln -s '$T/good.txt' '$C/$BL'")"
check "control after restore passes" 0 "$(corrupt "true")"

# what the tools print
S=$(newproj adapters)
TSC='src/x.ts(3,7): error TS2322: Type string is not assignable to type number.
  Types are incompatible here.
src/y.ts(10,1): error TS2304: Cannot find name foo.

Found 2 errors in 2 files.'
out=$(printf '%s\n' "$TSC" | gb "$S" record types tsc); check "tsc record exits 0" 0 $?
contains "tsc continuation joins the fingerprint" "Types are incompatible here" "$(cat "$S/$BL")"
printf '%s\n' "$TSC" | gb "$S" check types tsc >/dev/null; check "tsc control passes" 0 $?
printf '%s\n' "$TSC" | sed 's/(3,7)/(33,7)/' | gb "$S" check types tsc >/dev/null; check "tsc moved finding passes" 0 $?
printf '%s\n%s\n' "$TSC" 'src/z.ts(1,1): error TS1005: expected.' | gb "$S" check types tsc >/dev/null; check "tsc new finding fails" 1 $?
PYR='/abs/proj/app/m.py
  /abs/proj/app/m.py:4:5 - error: "x" is not defined (reportUndefinedVariable)
1 error, 0 warnings, 0 informations'
out=$(printf '%s\n' "$PYR" | gb "$S" record types pyright); check "recording into a gate that has other entries is refused" 1 $?
printf '%s\n' "$PYR" | gb "$S" record pyr pyright >/dev/null; check "pyright record" 0 $?
printf '%s\n' "$PYR" | sed 's/4:5/40:5/' | gb "$S" check pyr pyright >/dev/null; check "pyright moved finding passes" 0 $?
printf '%s\n' "$PYR" | sed 's#reportUndefinedVariable#reportOther#' | gb "$S" check pyr pyright >/dev/null; check "pyright changed rule fails" 1 $?
out=$(printf '%s\n' "$OLD" | gb "$S" check lint colon); check "a gate with no entries blocks every finding" 1 $?
out=$(printf 'Error: Cannot find module eslint.config.js\n' | gb "$P" check lint colon --rc 2); check "a crashed tool is not a clean run" 1 $?
contains "crash line is shown" "cannot be baselined" "$out"
out=$(gb "$P" check lint colon --rc 2 </dev/null); check "rc 2 with no output fails" 1 $?
out=$(gb "$P" check lint colon --rc 0 </dev/null); check "rc 0 passes" 0 $?
out=$(printf '%s\nweird line\n' "$OLD" | gb "$P" check lint colon); check "an unreadable extra line fails even when findings are old" 1 $?

# paths with spaces
SP=$(newproj "sp ace")
SPP=$(cd "$SP" && pwd -P)
printf 'src/my file.ts:2:2: Bad name [Error/n]\n%s/src/abs path.ts:1:1: Abs [Error/a]\n' "$SPP" | gb "$SP" record lint colon >/dev/null; check "record with spaces" 0 $?
contains "absolute path is made relative" "lint${tab}src/abs path.ts${tab}1${tab}Abs" "$(cat "$SP/$BL")"
printf 'src/my file.ts:7:2: Bad name [Error/n]\n' | gb "$SP" check lint colon >/dev/null; check "spaces: old finding passes" 0 $?
printf 'src/my file.ts:7:2: Bad name [Error/n]\nsrc/other file.ts:1:1: Bad name [Error/n]\n' | gb "$SP" check lint colon >/dev/null; check "spaces: new finding fails" 1 $?

# run: the helper runs the project's tools itself (stubs)
R=$(newproj runproj)
mkdir -p "$R/node_modules" "$R/scripts" "$T/stubbin"
printf '{}\n' >"$R/package.json"; printf 'export default []\n' >"$R/eslint.config.mjs"; printf '{}\n' >"$R/tsconfig.json"
cat >"$T/stubbin/pnpm" <<'STUB'
#!/usr/bin/env bash
case "$2" in
  eslint) cat "$STUB_LINT"; if [ -n "${STUB_ERR:-}" ]; then cat "$STUB_ERR" >&2; fi; if [ -n "${STUB_LINT_RC:-}" ]; then exit "$STUB_LINT_RC"; fi; [ -s "$STUB_LINT" ] && exit 1; exit 0 ;;
  tsc) cat "$STUB_TSC"; [ -s "$STUB_TSC" ] && exit 2; exit 0 ;;
esac
exit 3
STUB
chmod +x "$T/stubbin/pnpm"
printf '%s\n' "$OLD" >"$T/lint.txt"; printf '%s\n' "$TSC" >"$T/tsc.txt"
runh() { STUB_LINT="$T/lint.txt" STUB_TSC="$T/tsc.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R" run "$@" 2>&1; }
out=$(runh dry); check "run dry exits 0" 0 $?
contains "run dry reports lint" "lint would record 3 finding(s)" "$out"
contains "run dry reports types" "types would record 2 finding(s)" "$out"
exists=no; [ -e "$R/$BL" ] && exists=yes; check "run dry writes nothing" no "$exists"
out=$(runh record); check "run record exits 0" 0 $?
check "run record wrote both gates' entries" 5 "$(nent "$R/$BL")"
check "run record wrote the tools" "# gate${tab}lint${tab}eslint # gate${tab}types${tab}tsc" "$(grep '^# gate' "$R/$BL" | tr '\n' ' ' | sed 's/ $//')"
out=$(runh check); check "run check passes on the recorded state" 0 $?
printf '%s\nsrc/n.ts:1:1: New [Error/n]\n' "$OLD" >"$T/lint.txt"
out=$(runh check); check "run check fails on a new lint finding" 1 $?
printf '%s\n' "$OLD" >"$T/lint.txt"
rm -rf "${R:?}/node_modules"
out=$(runh check); check "run check fails when a baselined tool cannot run" 1 $?
contains "skipped tool is explained" "cannot run here" "$out"

# harness-refresh: bare --baseline records, a dry run writes nothing
A=$(newproj adopt)
printf '{"dependencies":{"@nestjs/core":"1"}}\n' >"$A/package.json"; printf '{}\n' >"$A/nest-cli.json"
printf 'export default []\n' >"$A/eslint.config.mjs"; printf '{}\n' >"$A/tsconfig.json"; mkdir -p "$A/node_modules" "$A/src with space"
echo 'x' >"$A/src with space/f.ts"
printf 'node_modules\n' >"$A/.gitignore"
(cd "$A" && git init -q -b main && git add -A && gitc commit -qm init) >/dev/null 2>&1
refresh() { STUB_LINT="$T/lint.txt" STUB_TSC="$T/tsc.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$REFRESH" "$A" "$@" 2>&1; }
h0=$(treehash "$A")
out=$(refresh --baseline); contains "dry run prints what would be recorded" "lint would record 3 finding(s)" "$out"
check "dry run with --baseline writes nothing" "$h0" "$(treehash "$A")"
refresh >/dev/null
check "plain dry run writes nothing either" "$h0" "$(treehash "$A")"
bash "$REFRESH" "$A" --baseline "$T" >/dev/null 2>&1; check "--baseline <dir> without --apply still exits 2" 2 $?
bash "$REFRESH" "$A" --prune >/dev/null 2>&1; check "--prune alone exits 2" 2 $?
bash "$REFRESH" "$A" --apply --baseline --prune >/dev/null 2>&1; check "--prune without a file exits 2" 2 $?
out=$(refresh --apply --baseline)
contains "apply records lint" "lint recorded 3 finding(s)" "$out"
contains "apply records types" "types recorded 2 finding(s)" "$out"
exists=no; [ -f "$A/$BL" ] && exists=yes; check "apply wrote the baseline file" yes "$exists"
exists=no; [ -x "$A/scripts/gate-baseline.sh" ] && exists=yes; check "apply copied an executable helper" yes "$exists"
cmp -s "$G" "$A/scripts/gate-baseline.sh"; check "the copied helper is the plugin's" 0 $?
out=$(STUB_LINT="$T/lint.txt" STUB_TSC="$T/tsc.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$A/scripts/gate-baseline.sh" -C "$A" run check 2>&1); rc=$?; check "the project's own copy passes run check" 0 $rc; [ "$rc" = 0 ] || echo "$out"
h2=$(sha "$A/$BL")
(cd "$A" && git add -A && gitc commit -qm adopt)
out=$(refresh --apply --baseline)
check "a second apply keeps the baseline byte-identical" "$h2" "$(sha "$A/$BL")"
contains "second apply reports unchanged" "lint unchanged" "$out"
printf '%s\n' "$FIXED" >"$T/lint.txt"
out=$(refresh --apply --baseline --allow-dirty); contains "a shrunk gate is not re-recorded without --prune" "already baselined" "$out"
check "the file did not change without --prune" "$h2" "$(sha "$A/$BL")"
out=$(refresh --apply --baseline --prune --allow-dirty)
contains "--prune lowers the baseline" "1 entr(ies) removed" "$out"
check "the file shrank with --prune" 4 "$(nent "$A/$BL")"
printf '%s\nsrc/n.ts:1:1: New [Error/n]\n' "$FIXED" >"$T/lint.txt"
out=$(refresh --apply --baseline --prune --allow-dirty); check "--prune never adds a new finding" 0 "$(grep -c 'New \[Error' "$A/$BL")"


# run check: a gate with no baseline entries still blocks new findings
R2=$(newproj emptybl)
mkdir -p "$R2/node_modules" "$R2/.claude"
printf '{}\n' >"$R2/package.json"; printf 'export default []\n' >"$R2/eslint.config.mjs"; printf '{}\n' >"$R2/tsconfig.json"
printf '%s\n' "$HEADER_LINE" >"$R2/$BL"
: >"$T/empty.txt"
runh2() { STUB_LINT="$T/lint2.txt" STUB_TSC="$T/empty.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R2" run "$@" 2>&1; }
: >"$T/lint2.txt"
out=$(runh2 check); check "empty baseline, clean gate passes" 0 $?
printf 'a.ts:1:1: NEW [Error/new]\n' >"$T/lint2.txt"
out=$(runh2 check); check "empty baseline, new lint finding fails" 1 $?
contains "empty baseline names the finding" "NEW lint: a.ts" "$out"
printf '%s\n# gate\ttypes\ttsc\ntypes\tsrc/x.ts\t1\tType problem\n' "$HEADER_LINE" >"$R2/$BL"
: >"$T/lint2.txt"
out=$(runh2 check); check "entries only for another gate, clean lint passes" 0 $?
printf 'a.ts:1:1: NEW [Error/new]\n' >"$T/lint2.txt"
out=$(runh2 check); check "entries only for another gate, new lint finding fails" 1 $?
printf 'Error: crashed\n' >"$T/lint2.txt"
out=$(runh2 check); check "a crashed tool on a gate with no entries fails" 1 $?
rm -rf "${R2:?}/node_modules"
out=$(runh2 check); check "a configured gate whose tool cannot run fails even with no entries" 1 $?
contains "cannot-run reason is shown" "cannot run here" "$out"
rm -f "${R2:?}/eslint.config.mjs" "${R2:?}/tsconfig.json"
printf '%s\n' "$HEADER_LINE" >"$R2/$BL"
out=$(runh2 check); check "a gate that does not apply (no config) is skipped" 0 $?
contains "skip is explained" "does not apply" "$out"

# workflows: no workflow file means the gate does not apply; a file means it runs
R3=$(newproj wfproj)
mkdir -p "$R3/scripts" "$R3/.claude"
printf '#!/usr/bin/env bash\necho "check-workflows: no workflow or pipeline file found" >&2\nexit 1\n' >"$R3/scripts/check-workflows.sh"
printf '%s\n' "$HEADER_LINE" >"$R3/$BL"
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R3" run check 2>&1); check "no workflow files: gate does not apply" 0 $?
mkdir -p "$R3/.github/workflows"; : >"$R3/.github/workflows/ci.yml"
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R3" run check 2>&1); check "a workflow file makes the gate run, and its failure counts" 1 $?

# run prune: a gate with entries whose tool cannot run fails
R4=$(newproj prunefail)
mkdir -p "$R4/.claude"; printf '{}\n' >"$R4/package.json"; printf 'export default []\n' >"$R4/eslint.config.mjs"
printf '%s\n# gate\tlint\teslint\nlint\ta.ts\t1\tOld [Error/old]\n' "$HEADER_LINE" >"$R4/$BL"
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R4" run prune 2>&1); check "run prune fails when the tool cannot run" 1 $?
mkdir -p "$R4/node_modules"; printf 'a.ts:1:1: Old [Error/old]\n' >"$T/lint4.txt"
out=$(STUB_LINT="$T/lint4.txt" STUB_TSC="$T/empty.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R4" run prune 2>&1); check "control: run prune with a working tool passes" 0 $?

# rc 0 does not hide output
out=$(printf '%s\nsrc/new.ts:1:1: Sneaky [Error/s]\n' "$OLD" | gb "$P" check lint colon --rc 0); check "rc 0 with a new finding fails" 1 $?
out=$(printf '%s\n' "$OLD" | gb "$P" check lint colon --rc 0); check "control: rc 0 with only old findings passes" 0 $?
out=$(printf '%s\nwhat is this\n' "$OLD" | gb "$P" check lint colon --rc 0); check "rc 0 ignores a line that is not a finding" 0 $?
out=$(printf '%s\nwhat is this\n' "$OLD" | gb "$P" check lint colon --rc 1); check "control: rc 1 fails on the same line" 1 $?
out=$(printf 'check-workflows: ok (2 files)\n' | gb "$P" check lint colon --rc 0); check "rc 0 success banner passes" 0 $?

# tool output quirks
Q=$(newproj quirks)
printf 'src/a.ts:3:1: Unexpected any [Error/no-any]\r\nsrc/b.ts:1:1: Two  spaced\tby tab and back\\slash\r\n' | gb "$Q" record lint colon >/dev/null
check "CRLF record exits 0" 0 $?
absent "no carriage return in the file" "$(printf '\r')" "$(cat "$Q/$BL")"
printf 'src/a.ts:9:1: Unexpected any [Error/no-any]\r\nsrc/b.ts:7:1: Two spaced by tab and back\\slash\r\n' | gb "$Q" check lint colon >/dev/null; check "CRLF and whitespace differences still match" 0 $?
printf 'src/b.ts:7:1: Two spaced by tab and back/slash\n' | gb "$Q" check lint colon >/dev/null; check "a different backslash is a different finding" 1 $?
printf 'src/a.ts:3:1: Unexpected any [Error/no-any]\n' | gb "$Q" check lint colon >/dev/null; check "control: LF output of the old finding passes" 0 $?
ESC=$(printf '\033')
printf '%s[31msrc/a.ts:3:1:%s[0m Unexpected any [Error/no-any]\n%s[1msrc/b.ts:1:1: Two spaced by tab and back\\slash%s[0m\n' "$ESC" "$ESC" "$ESC" "$ESC" | gb "$Q" check lint colon >/dev/null; check "colour codes are stripped" 0 $?
printf -- '-dash.ts:1:1: Dash [Error/d]\nsrc/é ü.ts:2:2: Accent [Error/a]\n' | gb "$Q" record types colon >/dev/null; check "leading dash and non-ASCII names record" 0 $?
printf -- '-dash.ts:5:1: Dash [Error/d]\nsrc/é ü.ts:9:2: Accent [Error/a]\n' | gb "$Q" check types colon >/dev/null; check "leading dash and non-ASCII names match" 0 $?
printf -- '-dash.ts:5:1: Dash [Error/d]\nsrc/é ü.ts:9:2: Accent [Error/a]\nsrc/ü.ts:1:1: Accent [Error/a]\n' | gb "$Q" check types colon >/dev/null; check "a non-ASCII new file fails" 1 $?

# validate: a carriage return in an entry; format only
CR=$(newproj crfile)
mkdir -p "$CR/.claude"
printf '%s\n# gate\tlint\tcolon\nlint\ta.ts\t1\tOld\r\n' "$HEADER_LINE" >"$CR/$BL"
out=$(gb "$CR" validate); check "an entry with a carriage return fails validate" 1 $?
printf '%s\n# gate\tlint\tcolon\nlint\ta.ts\t1\tOld\n' "$HEADER_LINE" >"$CR/$BL"
out=$(gb "$CR" validate); check "control: the same entry without it passes" 0 $?

# growth: not a repository, unreadable file, subdirectory, absolute -f
NG=$(newproj nogit)
out=$(gb "$NG" growth HEAD); check "growth outside a repository exits 2" 2 $?
UN=$(newproj unreadable)
printf '%s\n' "$OLD" | gb "$UN" record lint colon >/dev/null
chmod 000 "$UN/$BL"
out=$(printf '%s\n' "$OLD" | gb "$UN" check lint colon); check "an unreadable baseline file exits 2" 2 $?
chmod 644 "$UN/$BL"
out=$(printf '%s\n' "$OLD" | gb "$UN" check lint colon); check "control: readable again passes" 0 $?
SUB=$(newproj subrepo)
(cd "$SUB" && git init -q -b main && mkdir app && echo x >app/f) >/dev/null 2>&1
(cd "$SUB" && git add -A && gitc commit -qm base)
printf '%s\n' "$OLD" | gb "$SUB/app" record lint colon >/dev/null
(cd "$SUB" && git add -A && gitc commit -qm add)
out=$(gb "$SUB/app" growth HEAD~1); check "growth from a subdirectory sees the file" 1 $?
contains "subdirectory growth names the file" "WEAKENED .claude/gate-baseline.txt" "$out"
out=$(gb "$SUB/app" growth HEAD); check "control: subdirectory, same commit, no growth" 0 $?
out=$(bash "$G" -C "$SUB/app" -f "$SUB/app/$BL" growth HEAD~1 2>&1); check "growth with an absolute -f exits 2" 2 $?

# round 2: a finding line is a finding even when it starts like a summary
FF=$(newproj findfirst)
printf 'old.ts:1:1: Old\n' | gb "$FF" record lint colon >/dev/null
out=$(printf 'old.ts:1:1: Old\n' | gb "$FF" check lint colon); check "control: only the old finding passes" 0 $?
out=$(printf 'old.ts:1:1: Old\n1 error.ts:1:1: New\n' | gb "$FF" check lint colon); check "a file named '1 error.ts' is a finding" 1 $?
contains "the file named like a summary is reported" "NEW lint: 1 error.ts" "$out"
out=$(printf 'old.ts:1:1: Old\n2 errors/x.ts:1:1: New\n' | gb "$FF" check lint colon); check "a folder named '2 errors/' is a finding" 1 $?
out=$(printf 'old.ts:1:1: Old\ncheck-workflows: ok a.ts:1:1: New\n' | gb "$FF" check lint colon); check "a finding after 'check-x: ok' is a finding" 1 $?
out=$(printf 'old.ts:1:1: Old\n\n1 problem\n' | gb "$FF" check lint colon); check "control: the real summary line passes" 0 $?
out=$(printf 'old.ts:1:1: Old\n1 problem found nearby\n' | gb "$FF" check lint colon); check "a summary pattern is anchored at the end" 1 $?
out=$(printf 'old.ts:1:1: Old\ncheck-workflows: ok (2 files) extra\n' | gb "$FF" check lint colon); check "the ok banner is anchored at the end" 1 $?

# round 2: escape sequences
BEL=$(printf '\007')
printf '%s[?25lsrc/a.ts:3:1: Unexpected any [Error/no-any]%s[?25h\n' "$ESC" "$ESC" | gb "$Q" check lint colon >/dev/null; check "ESC [ ? 25 l is stripped" 0 $?
printf '%s]8;;http://h/x%s\\src/a.ts:3:1: Unexpected any [Error/no-any]%s]8;;%s\\\n' "$ESC" "$ESC" "$ESC" "$ESC" | gb "$Q" check lint colon >/dev/null; check "an OSC 8 hyperlink ended by ESC backslash is stripped" 0 $?
printf '%s]8;;http://h/x%ssrc/a.ts:3:1: Unexpected any [Error/no-any]%s]8;;%s\n' "$ESC" "$BEL" "$ESC" "$BEL" | gb "$Q" check lint colon >/dev/null; check "an OSC 8 hyperlink ended by BEL is stripped" 0 $?
printf '%s]8;;http://h/x%ssrc/new.ts:3:1: Unexpected any [Error/no-any]%s]8;;%s\n' "$ESC" "$BEL" "$ESC" "$BEL" | gb "$Q" check lint colon >/dev/null; check "control: a new finding inside a hyperlink still fails" 1 $?

# round 2: tool noise passes at rc 0 and fails at a non-zero rc
NOISE='WARN  Unsupported engine: wanted node 26
(node:123) ExperimentalWarning: something
npm notice New version available'
out=$(printf '%s\n%s\n' "$NOISE" "$OLD" | gb "$P" check lint colon --rc 0); check "rc 0: package-manager and runtime noise is ignored" 0 $?
out=$(printf '%s\n%s\n' "$NOISE" "$OLD" | gb "$P" check lint colon --rc 1); check "rc 1: the same noise fails" 1 $?
out=$(printf '%s\n%s\nsrc/new.ts:1:1: Sneaky [Error/s]\n' "$NOISE" "$OLD" | gb "$P" check lint colon --rc 0); check "rc 0: a new finding between noise fails" 1 $?

# round 2: a version 1 file asks to record again
V1=$(newproj v1file)
mkdir -p "$V1/.claude"
printf '# templatecentral gate baseline v1\nlint\ta.ts\t1\tOld\n' >"$V1/$BL"
out=$(gb "$V1" validate); check "a v1 file fails validate" 1 $?
contains "the v1 message says to record again" "Record it again" "$out"
out=$(printf 'a.ts:1:1: Old\n' | gb "$V1" check lint colon); check "a v1 file fails check with exit 2" 2 $?

# round 2: a change cannot switch a gate off
RS=$(newproj switch)
mkdir -p "$RS/node_modules" "$RS/.claude" "$T/ruffbin"
printf '{}\n' >"$RS/package.json"; printf 'export default []\n' >"$RS/eslint.config.mjs"
cat >"$T/ruffbin/ruff" <<'STUB'
#!/usr/bin/env bash
cat "$STUB_RUFF"; exit "${STUB_RUFF_RC:-0}"
STUB
cat >"$T/ruffbin/pyright" <<'STUB'
#!/usr/bin/env bash
cat "$STUB_PYR"; exit "${STUB_PYR_RC:-0}"
STUB
chmod +x "$T/ruffbin/ruff" "$T/ruffbin/pyright"
printf '%s\n' "$OLD" >"$T/lint5.txt"; printf 'All checks passed!\n' >"$T/ruffok.txt"
runs() { local pth=$1; shift; STUB_LINT="$T/lint5.txt" STUB_TSC="$T/empty.txt" STUB_RUFF="$T/ruffok.txt" PATH="$pth:/usr/bin:/bin" bash "$G" -C "$RS" run "$@" 2>&1; }
out=$(runs "$T/stubbin" record); check "switch: record exits 0" 0 $?
contains "switch: the gate line names eslint" "# gate${tab}lint${tab}eslint" "$(cat "$RS/$BL")"
out=$(runs "$T/stubbin" check); check "switch: control passes" 0 $?
mv "$RS/eslint.config.mjs" "$RS/eslint-cfg.mjs"
out=$(runs "$T/ruffbin:$T/stubbin" check); check "switch: renamed config with a clean ruff on PATH fails" 1 $?
contains "switch: the tool change is named" "ran with 'ruff'" "$out"
out=$(runs "$T/stubbin" check); check "switch: renamed config with no ruff fails" 1 $?
contains "switch: the recorded gate cannot run" "cannot run here" "$out"
out=$(runs "$T/ruffbin:$T/stubbin" prune); check "switch: prune with another tool fails" 1 $?
out=$(runs "$T/stubbin" prune); check "switch: prune with no tool fails" 1 $?
mv "$RS/eslint-cfg.mjs" "$RS/eslint.config.mjs"
out=$(runs "$T/stubbin" check); check "switch: control passes again with the config back" 0 $?
RS2=$(newproj neverhad)
mkdir -p "$RS2/.claude"; printf '%s\n' "$HEADER_LINE" >"$RS2/$BL"
out=$(STUB_RUFF="$T/ruffok.txt" PATH="$T/ruffbin:/usr/bin:/bin" bash "$G" -C "$RS2" run check 2>&1); check "a project that never had the gate passes with a clean ruff" 0 $?
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$RS2" run check 2>&1); check "a project that never had the gate skips it" 0 $?
contains "the skip is explained" "does not apply" "$out"

# round 2: the gate line is covered by growth
GR=$(newproj gline)
(cd "$GR" && git init -q -b main) >/dev/null 2>&1
printf '%s\n' "$OLD" | gb "$GR" record lint colon >/dev/null
printf 'a.ts:1:1: E\n' | gb "$GR" record types colon --tool tsc >/dev/null
printf 'check-dockerfile: ok (1 file)\n' | gb "$GR" record dockerfile colon --tool script --rc 0 >/dev/null
(cd "$GR" && git add -A && gitc commit -qm base && git tag base)
out=$(gb "$GR" growth base); check "gate lines: control, no change" 0 $?
grep -v "^# gate${tab}dockerfile${tab}" "$GR/$BL" >"$T/gl1.txt" && cp "$T/gl1.txt" "$GR/$BL"
(cd "$GR" && git add -A && gitc commit -qm "drop empty gate")
out=$(gb "$GR" growth base); check "removing the gate line of a gate with no findings fails" 1 $?
contains "the removed gate is named" "the gate line for dockerfile" "$out"
(cd "$GR" && gitc reset -q --hard base)
grep -v -e "^# gate${tab}types${tab}" -e "^types${tab}" "$GR/$BL" >"$T/gl2.txt" && cp "$T/gl2.txt" "$GR/$BL"
(cd "$GR" && git add -A && gitc commit -qm "drop types")
out=$(gb "$GR" growth base); check "removing a gate with its entries fails" 1 $?
(cd "$GR" && gitc reset -q --hard base)
sed "s/^# gate${tab}lint${tab}colon/# gate${tab}lint${tab}other/" "$GR/$BL" >"$T/gl3.txt" && cp "$T/gl3.txt" "$GR/$BL"
(cd "$GR" && git add -A && gitc commit -qm "change tool")
out=$(gb "$GR" growth base); check "changing the tool of a gate fails" 1 $?
contains "the tool change is named" "the tool of gate lint changed" "$out"
(cd "$GR" && gitc reset -q --hard base)
out=$(gb "$GR" growth base); check "control: back at base passes" 0 $?

# round 2: growth refuses a path outside the project or a wrong folder
GT=$(newproj growpath)
(cd "$GT" && git init -q -b main && mkdir app && echo x >app/f) >/dev/null 2>&1
printf '%s\n' "$OLD" | gb "$GT" record lint colon >/dev/null
(cd "$GT" && git add -A && gitc commit -qm base)
out=$(gb "$GT" growth HEAD); check "growth path: control at the project root" 0 $?
out=$(gb "$GT/app" growth HEAD); check "growth in a folder without the baseline exits 2" 2 $?
contains "the wrong folder is explained" "probably wrong" "$out"
out=$(gb "$GT" -f ../x growth HEAD); check "growth with -f ../x exits 2" 2 $?
out=$(gb "$GT" -f .claude/../gate-baseline.txt growth HEAD); check "growth with a .. segment exits 2" 2 $?
out=$(gb "$GT" -f .claude/gate-baseline.txt growth HEAD); check "control: -f with the real relative path passes" 0 $?
GN=$(newproj nobl)
(cd "$GN" && git init -q -b main && echo x >f && git add -A && gitc commit -qm base) >/dev/null 2>&1
out=$(gb "$GN" growth HEAD); check "control: a repository that never had a baseline passes" 0 $?

# round 2: the full-line summaries of check-dockerfile.sh
DK=$(newproj dockerline)
printf 'Dockerfile:1: base image x is not pinned by digest.\n' | gb "$DK" record dockerfile colon >/dev/null
out=$(printf 'Dockerfile:1: base image x is not pinned by digest.\ncheck-dockerfile: no Dockerfile found, nothing to check\n' | gb "$DK" check dockerfile colon --rc 1); check "the no Dockerfile line is a summary" 0 $?
out=$(printf 'Dockerfile:1: base image x is not pinned by digest.\nWARNING check-dockerfile: hadolint is not installed, so the Dockerfile was only linted by the built-in rules; CI runs hadolint and will fail on what it finds.\nWARNING check-dockerfile: install it with: brew install hadolint   (Linux: https://github.com/hadolint/hadolint/releases)\n' | gb "$DK" check dockerfile colon --rc 1); check "the WARNING check-dockerfile lines are summaries" 0 $?
out=$(printf 'Dockerfile:1: base image x is not pinned by digest.\nWARNING check-other: something\n' | gb "$DK" check dockerfile colon --rc 1); check "control: another WARNING line fails" 1 $?
out=$(printf 'Dockerfile:1: base image x is not pinned by digest.\ncheck-dockerfile: hadolint is not installed, and CI never skips it. Run it through ci-gates.sh dockerfile, which installs the pinned release.\n' | gb "$DK" check dockerfile colon --rc 1); check "control: the CI hadolint-missing line fails" 1 $?

# round 2: the Dockerfile skip and the workflow globs
DF=$(newproj dfskip)
mkdir -p "$DF/scripts" "$DF/.claude" "$DF/node_modules"
printf '#!/usr/bin/env bash\necho "check-dockerfile: boom" >&2\nexit 1\n' >"$DF/scripts/check-dockerfile.sh"
printf '%s\n' "$HEADER_LINE" >"$DF/$BL"
out=$(bash "$G" -C "$DF" run check 2>&1); check "no Dockerfile: the gate does not apply" 0 $?
: >"$DF/node_modules/Dockerfile"
out=$(bash "$G" -C "$DF" run check 2>&1); check "a Dockerfile under node_modules does not count" 0 $?
: >"$DF/Dockerfile"
out=$(bash "$G" -C "$DF" run check 2>&1); check "a Dockerfile makes the gate run, and its failure counts" 1 $?
rm -f "${DF:?}/Dockerfile"; mkdir -p "$DF/sub"; : >"$DF/sub/Dockerfile.prod"
out=$(bash "$G" -C "$DF" run check 2>&1); check "a nested Dockerfile.prod makes the gate run" 1 $?
glob_case() {
  local d rc
  d=$(newproj "glob-$1"); mkdir -p "$d/scripts" "$d/.claude" "$(dirname "$d/$2")"
  printf '#!/usr/bin/env bash\necho "check-workflows: boom" >&2\nexit 1\n' >"$d/scripts/check-workflows.sh"
  printf '%s\n' "$HEADER_LINE" >"$d/$BL"
  : >"$d/$2"
  out=$(bash "$G" -C "$d" run check 2>&1); rc=$?
  check "$1 makes the workflows gate run" 1 "$rc"
}
glob_case yaml .github/workflows/ci.yaml
glob_case azroot azure-pipelines.yml
glob_case azdir azure-pipelines/build.yml
glob_case actyml .github/actions/x/action.yml
glob_case actyaml .github/actions/x/action.yaml
GO=$(newproj glob-none)
mkdir -p "$GO/scripts" "$GO/.claude" "$GO/notes"
printf '#!/usr/bin/env bash\nexit 1\n' >"$GO/scripts/check-workflows.sh"; : >"$GO/notes/ci.yml"
printf '%s\n' "$HEADER_LINE" >"$GO/$BL"
out=$(bash "$G" -C "$GO" run check 2>&1); check "control: a yml file outside the workflow folders does not count" 0 $?

# round 2: the ruff, pyright and hadolint paths with stubs on PATH
RF=$(newproj ruffproj)
mkdir -p "$RF/.claude"
printf 'app/m.py:1:8: F401 [*] os imported but unused\napp/m.py:3:1: E402 Module level import not at top of file\nFound 2 errors.\n[*] 1 fixable with the \140--fix\140 option.\n' >"$T/ruff2.txt"
runr() { STUB_RUFF="$T/ruff2.txt" STUB_RUFF_RC="${RUFF_RC:-1}" PATH="$T/ruffbin:/usr/bin:/bin" bash "$G" -C "$RF" run "$@" 2>&1; }
out=$(runr record); check "ruff: record exits 0" 0 $?
check "ruff: both findings are entries" 2 "$(nent "$RF/$BL")"
contains "ruff: the gate line names ruff" "# gate${tab}lint${tab}ruff" "$(cat "$RF/$BL")"
out=$(runr check); check "ruff: control passes" 0 $?
printf 'app/m.py:9:1: F401 [*] os imported but unused\napp/m.py:30:1: E402 Module level import not at top of file\nFound 2 errors.\n' >"$T/ruff2.txt"
out=$(runr check); check "ruff: moved findings pass" 0 $?
printf 'app/m.py:1:8: F401 [*] os imported but unused\napp/m.py:3:1: E402 Module level import not at top of file\napp/n.py:1:1: F821 Undefined name x\n' >"$T/ruff2.txt"
out=$(runr check); check "ruff: a new finding fails" 1 $?
contains "ruff: the new finding is named" "NEW lint: app/n.py" "$out"
PYP=$(newproj pyproj)
mkdir -p "$PYP/.claude"; printf '{}\n' >"$PYP/pyrightconfig.json"
printf '/abs/proj/app/m.py\n  /abs/proj/app/m.py:4:5 - error: "x" is not defined (reportUndefinedVariable)\n1 error, 0 warnings, 0 informations \n' >"$T/pyr2.txt"
runp() { STUB_PYR="$T/pyr2.txt" STUB_PYR_RC=1 PATH="$T/ruffbin:/usr/bin:/bin" bash "$G" -C "$PYP" run "$@" 2>&1; }
out=$(runp record); check "pyright: record exits 0" 0 $?
check "pyright: one entry" 1 "$(nent "$PYP/$BL")"
contains "pyright: the gate line names pyright" "# gate${tab}types${tab}pyright" "$(cat "$PYP/$BL")"
out=$(runp check); check "pyright: control passes" 0 $?
sed 's/4:5/44:5/' "$T/pyr2.txt" >"$T/pyr3.txt"; cp "$T/pyr3.txt" "$T/pyr2.txt"
out=$(runp check); check "pyright: a moved finding passes" 0 $?
sed 's/reportUndefinedVariable/reportOther/' "$T/pyr2.txt" >"$T/pyr3.txt"; cp "$T/pyr3.txt" "$T/pyr2.txt"
out=$(runp check); check "pyright: a changed rule fails" 1 $?
HD=$(newproj hado)
mkdir -p "$HD/scripts" "$HD/.claude" "$T/hadobin"
cp "$ROOT/skills/scaffold/shared/template/scripts/check-dockerfile.sh" "$HD/scripts/check-dockerfile.sh"
printf 'FROM node:22@sha256:%064d\nUSER 1000\n' 0 >"$HD/Dockerfile"
cat >"$T/hadobin/hadolint" <<'STUB'
#!/usr/bin/env bash
cat "$STUB_HADO"; exit "${STUB_HADO_RC:-0}"
STUB
chmod +x "$T/hadobin/hadolint"
printf 'Dockerfile:2 DL3059 info: Multiple consecutive RUN instructions. Consider consolidation.\n' >"$T/hado.txt"
runhd() { STUB_HADO="$T/hado.txt" STUB_HADO_RC="${HADO_RC:-1}" PATH="$T/hadobin:/usr/bin:/bin" bash "$G" -C "$HD" run "$@" 2>&1; }
out=$(runhd record); check "hadolint: record exits 0" 0 $?
check "hadolint: the finding is one entry" 1 "$(nent "$HD/$BL")"
contains "hadolint: the entry has the code and message" "Dockerfile${tab}1${tab}DL3059 info: Multiple consecutive" "$(cat "$HD/$BL")"
out=$(runhd check); check "hadolint: control passes with its summary line in the output" 0 $?
sed 's/Dockerfile:2/Dockerfile:7/' "$T/hado.txt" >"$T/hado2.txt"; cp "$T/hado2.txt" "$T/hado.txt"
out=$(runhd check); check "hadolint: a moved finding passes" 0 $?
printf 'Dockerfile:7 DL3059 info: Multiple consecutive RUN instructions. Consider consolidation.\nDockerfile:9 DL3025 warning: Use arguments JSON notation for CMD and ENTRYPOINT arguments\n' >"$T/hado.txt"
out=$(runhd check); check "hadolint: a new finding fails" 1 $?
contains "hadolint: the new finding is named" "NEW dockerfile: Dockerfile: DL3025 warning" "$out"
HADO_RC=0; : >"$T/hado.txt"
out=$(runhd check); check "hadolint: clean output passes" 0 $?

# round 3: a script gate that prints nothing did not run
SG=$(newproj silent)
mkdir -p "$SG/scripts" "$SG/.claude"; printf 'FROM scratch\n' >"$SG/Dockerfile"
printf '#!/usr/bin/env bash\necho "Dockerfile:1: Use a pinned base image" >&2\necho "Dockerfile:2: Add a USER" >&2\nexit 1\n' >"$SG/scripts/check-dockerfile.sh"
out=$(bash "$G" -C "$SG" run record 2>&1); check "script gate: record exits 0" 0 $?
check "script gate: two entries recorded" 2 "$(nent "$SG/$BL")"
out=$(bash "$G" -C "$SG" run check 2>&1); check "script gate: control passes" 0 $?
printf '#!/usr/bin/env bash\nexit 0\n' >"$SG/scripts/check-dockerfile.sh"
out=$(bash "$G" -C "$SG" run check 2>&1); check "script gate: a silent script fails run check" 1 $?
contains "script gate: the silence is explained" "did not run" "$out"
out=$(bash "$G" -C "$SG" run prune 2>&1); check "script gate: a silent script fails run prune" 1 $?
SG2=$(newproj silent2)
mkdir -p "$SG2/scripts"; printf 'FROM scratch\n' >"$SG2/Dockerfile"; cp "$SG/scripts/check-dockerfile.sh" "$SG2/scripts/"
out=$(bash "$G" -C "$SG2" run record 2>&1); check "script gate: a silent script fails run record" 1 $?
exists=no; [ -f "$SG2/$BL" ] && exists=yes; check "script gate: nothing was written" no "$exists"
printf '#!/usr/bin/env bash\necho "check-dockerfile: ok (1 file)"\n' >"$SG2/scripts/check-dockerfile.sh"
out=$(bash "$G" -C "$SG2" run record 2>&1); check "script gate: control, an ok line records" 0 $?
out=$(bash "$G" -C "$SG2" run check 2>&1); check "script gate: control, an ok line passes run check" 0 $?

# round 3: trailing whitespace does not hide a summary
out=$(printf '%s\n1 problem  \t\n' "$OLD" | gb "$P" check lint colon --rc 1); check "a summary with trailing spaces is a summary" 0 $?

# round 3: record replaces a v1 file; check, prune, validate and growth keep failing on it
V3=$(newproj v1rec)
mkdir -p "$V3/.claude"; printf '# templatecentral gate baseline v1\nlint\ta.ts\t1\tOld\n' >"$V3/$BL"
out=$(printf 'a.ts:1:1: Old\n' | gb "$V3" record lint colon); check "record replaces a v1 file" 0 $?
contains "record says it replaced a v1 file" "NOTE" "$out"
check "the replacement is v2" "$HEADER_LINE" "$(head -n 1 "$V3/$BL")"
out=$(gb "$V3" validate); check "the replacement validates" 0 $?
V4=$(newproj v1refresh)
mkdir -p "$V4/node_modules" "$V4/.claude"
printf '{"dependencies":{"@nestjs/core":"1"}}\n' >"$V4/package.json"; printf '{}\n' >"$V4/nest-cli.json"
printf 'export default []\n' >"$V4/eslint.config.mjs"; printf 'node_modules\n' >"$V4/.gitignore"
printf '# templatecentral gate baseline v1\nlint\ta.ts\t1\tOld\n' >"$V4/$BL"
(cd "$V4" && git init -q -b main && git add -A && gitc commit -qm init) >/dev/null 2>&1
printf 'a.ts:1:1: Old\n' >"$T/lint6.txt"
out=$(STUB_LINT="$T/lint6.txt" STUB_TSC="$T/empty.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$REFRESH" "$V4" --apply --gate-baseline 2>&1)
check "harness-refresh replaces a v1 file" "$HEADER_LINE" "$(head -n 1 "$V4/$BL")"
check "the replacement keeps the finding" 1 "$(nent "$V4/$BL")"

# round 3: stderr noise does not fail a run; a crash with only stderr does
RE=$(newproj stderr)
mkdir -p "$RE/node_modules" "$RE/.claude"
printf '{}\n' >"$RE/package.json"; printf 'export default []\n' >"$RE/eslint.config.mjs"
printf '%s\n' "$OLD" >"$T/lint7.txt"
rune() { STUB_LINT="$T/lint7.txt" STUB_TSC="$T/empty.txt" STUB_ERR="${ERRF:-}" STUB_LINT_RC="${LRC:-}" PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$RE" run "$@" 2>&1; }
out=$(rune record); check "stderr: record exits 0" 0 $?
printf 'WARN deprecated package foo\n' >"$T/err7.txt"; ERRF="$T/err7.txt"
out=$(rune check); check "stderr: findings at rc 1 with a WARN line on stderr pass" 0 $?
ERRF=
printf 'a.ts:1:1: New [Error/n]\n%s\n' "$OLD" >"$T/lint7.txt"; ERRF="$T/err7.txt"
out=$(rune check); check "stderr: a new finding still fails with stderr noise" 1 $?
ERRF=; : >"$T/lint7.txt"; printf 'Error: eslint crashed\n' >"$T/err8.txt"; ERRF="$T/err8.txt"; LRC=2
out=$(rune check); check "stderr: a crash with only stderr text fails" 1 $?
contains "stderr: the crash text is shown" "eslint crashed" "$out"
ERRF=; LRC=2
out=$(rune check); check "stderr: a non-zero exit with no output fails" 1 $?
ERRF=; LRC=

# round 3: pyright configured but missing is a failure, not a skip
RPM=$(newproj pyrmissing)
mkdir -p "$RPM/.claude"; printf '{}\n' >"$RPM/pyrightconfig.json"
printf '%s\n# gate\ttypes\tpyright\ntypes\tapp/m.py\t1\tOld\n' "$HEADER_LINE" >"$RPM/$BL"
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$RPM" run check 2>&1); check "pyright: configured, binary missing fails run check" 1 $?
contains "pyright: the reason is named" "configured but not installed" "$out"
printf '%s\n' "$HEADER_LINE" >"$RPM/$BL"
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$RPM" run check 2>&1); check "pyright: configured, binary missing fails even when not recorded" 1 $?
rm -f "$RPM/pyrightconfig.json"
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$RPM" run check 2>&1); check "pyright: control, not configured is skipped" 0 $?

# round 3: record and run dry refuse a failed run with no output
out=$(: | gb "$P" record fresh colon --rc 1); check "record refuses rc 1 with empty output" 1 $?
out=$(: | gb "$P" record fresh colon --rc 0); check "control: record accepts rc 0 with empty output" 0 $?
RD=$(newproj dryfail)
mkdir -p "$RD/node_modules"; printf '{}\n' >"$RD/package.json"; printf 'export default []\n' >"$RD/eslint.config.mjs"
: >"$T/empty2.txt"
out=$(STUB_LINT="$T/empty2.txt" STUB_LINT_RC=2 STUB_TSC="$T/empty.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$RD" run dry 2>&1)
contains "run dry refuses a failed run with no output" "would NOT be recorded" "$out"
out=$(STUB_LINT="$T/empty2.txt" STUB_TSC="$T/empty.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$RD" run dry 2>&1)
contains "control: run dry on a clean run records zero" "lint would record 0 finding(s)" "$out"

if [ "$fail" -eq 0 ]; then echo "all migrate-baseline checks passed"; fi
exit "$fail"

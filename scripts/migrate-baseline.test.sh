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
HEADER_LINE='# templatecentral gate baseline v1'

OLD='src/a.ts:3:1: Unexpected any [Error/no-any]
src/a.ts:9:5: Unused variable x [Error/no-unused]
src/b.ts:1:1: Missing return type [Error/types]'

# record, and a rerun that changes nothing
P=$(newproj rec)
out=$(printf '%s\n\n3 problems\n' "$OLD" | gb "$P" record lint colon); check "record exits 0" 0 $?
contains "record counts findings" "recorded 3 finding(s) in 3 entr" "$out"
h1=$(sha "$P/$BL")
check "file starts with the header" "# templatecentral gate baseline v1" "$(head -n 1 "$P/$BL")"
contains "entry names gate, file, count, fingerprint" "lint${tab}src/a.ts${tab}1${tab}Unexpected any [Error/no-any]" "$(cat "$P/$BL")"
absent "no line number in the file" ":3:1" "$(cat "$P/$BL")"
out=$(printf '%s\n' "$OLD" | gb "$P" record lint colon); check "rerun exits 0" 0 $?
contains "rerun says unchanged" "unchanged" "$out"
check "rerun leaves the file byte-identical" "$h1" "$(sha "$P/$BL")"
out=$(gb "$P" validate); check "validate passes on a recorded file" 0 $?
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
check "prune removed the fixed entry" 2 "$(tail -n +2 "$P/$BL" | wc -l | tr -d ' ')"
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
  eslint) cat "$STUB_LINT"; [ -s "$STUB_LINT" ] && exit 1; exit 0 ;;
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
check "run record wrote both gates" 5 "$(tail -n +2 "$R/$BL" | wc -l | tr -d ' ')"
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
check "the file shrank with --prune" 4 "$(tail -n +2 "$A/$BL" | wc -l | tr -d ' ')"
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
printf '%s\ntypes\tsrc/x.ts\t1\tType problem\n' "$HEADER_LINE" >"$R2/$BL"
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
printf '%s\nlint\ta.ts\t1\tOld [Error/old]\n' "$HEADER_LINE" >"$R4/$BL"
out=$(PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R4" run prune 2>&1); check "run prune fails when the tool cannot run" 1 $?
mkdir -p "$R4/node_modules"; printf 'a.ts:1:1: Old [Error/old]\n' >"$T/lint4.txt"
out=$(STUB_LINT="$T/lint4.txt" STUB_TSC="$T/empty.txt" PATH="$T/stubbin:/usr/bin:/bin" bash "$G" -C "$R4" run prune 2>&1); check "control: run prune with a working tool passes" 0 $?

# rc 0 does not hide output
out=$(printf '%s\nsrc/new.ts:1:1: Sneaky [Error/s]\n' "$OLD" | gb "$P" check lint colon --rc 0); check "rc 0 with a new finding fails" 1 $?
out=$(printf '%s\n' "$OLD" | gb "$P" check lint colon --rc 0); check "control: rc 0 with only old findings passes" 0 $?
out=$(printf '%s\nwhat is this\n' "$OLD" | gb "$P" check lint colon --rc 0); check "rc 0 with an unreadable line fails" 1 $?
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
printf '%s\nlint\ta.ts\t1\tOld\r\n' "$HEADER_LINE" >"$CR/$BL"
out=$(gb "$CR" validate); check "an entry with a carriage return fails validate" 1 $?
printf '%s\nlint\ta.ts\t1\tOld\n' "$HEADER_LINE" >"$CR/$BL"
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

if [ "$fail" -eq 0 ]; then echo "all migrate-baseline checks passed"; fi
exit "$fail"

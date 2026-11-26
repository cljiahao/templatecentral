#!/usr/bin/env bash
# Edge-case test for skills/cleanup/remove-example/remove-example.sh: signals during the apply, files that change mid-run,
# failing writes and deletes, unreadable directories, special files, the manifest and usage checks, and the stderr/stdout split.
# scripts/remove-example.test.sh holds the lifecycle and the user-file traps; this file holds what needs a hook inside a run.
#
# How a hook works: a shim for one command (cp, rm, cat, mv, cmp) sits first in PATH of one run. When its arguments contain
# the marker text (after an optional number of earlier matches) it either fails once, or writes a ready file and waits for a go
# file. The test acts in that window (sends a signal, changes a file, makes a directory unwritable) and then writes the go
# file; the shim runs the real command and writes a done file. Every wait ends on one of these files or on the end of the
# script; a hang-only cap (300 s) stops a broken harness and prints "harness timeout".
# Signals go to a launcher that resets INT, TERM and HUP to their defaults and execs bash (a background job in a
# non-interactive shell starts with INT ignored).
#
# Each probe has a clean control or a mutant: the script with one check removed (an exact-string replace that fails when the
# text is not found exactly once), run on the same input, must give the dangerous outcome. The groups run in parallel (four at
# a time, each in its own temp directory) and print in a fixed order. Needs bash 3.2+, python3, find, shasum or sha256sum.
#
# Not probed (and why):
#   - awk reading the copy of an edited file rather than the file: a change between the copy and the awk run is caught by the
#     compare at the apply against the same copy, so a mutant gives the same outcome.
#   - a held name that already exists: the name holds the script's process id, so a test cannot create it first.
#   - rename or copy failing in the middle of one call, a full disk: need a fault inside one command.
#   - owner and ACL loss on an edited file: needs root and a second user.
#   - guards 2 to 4 of the four unreadable-directory finds fire only when the earlier finds are disabled (the first one stops
#     the run); each is shown to fire that way, not alone.
#   - SIGKILL and power loss: no handler can run; the header of the script lists the leftovers.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RX=$ROOT/skills/cleanup/remove-example
COPY=$ROOT/skills/scaffold/shared/tc-copy.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/rxedge.XXXXXX") || exit 1
cleanup() { if [ -d "$T" ]; then chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; fi; }
trap cleanup EXIT
NL='
'
NOTROOT=1
if [ "$(id -u)" -eq 0 ]; then NOTROOT=0; fi
command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 is needed"; exit 1; }

check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in [$3]" ;; esac; }
absent() { case "$3" in *"$2"*) echo "FAIL $1: [$2] found in [$3]" ;; *) echo "ok   $1" ;; esac; }
# treehash <dir>: one hash over every path under <dir> with its type, its mode and its bytes (or link target); mtimes are left out
treehash() {
  python3 - "$1" <<'PY2'
import hashlib, os, stat, sys
root = sys.argv[1]
out = hashlib.sha256()
for d, dirs, files in os.walk(root):
    dirs.sort()
    for n in sorted(dirs + files):
        p = os.path.join(d, n)
        st = os.lstat(p)
        rec = "%s %o %s" % (os.path.relpath(p, root), stat.S_IMODE(st.st_mode), stat.S_IFMT(st.st_mode))
        if stat.S_ISLNK(st.st_mode):
            rec += " -> " + os.readlink(p)
        elif stat.S_ISREG(st.st_mode):
            with open(p, "rb") as f:
                rec += " " + hashlib.sha256(f.read()).hexdigest()
        out.update(rec.encode("utf-8", "surrogateescape") + b"\n")
print(out.hexdigest())
PY2
}
exists01() { if [ -e "$1" ] || [ -L "$1" ]; then echo 1; else echo 0; fi; }
changed01() { if [ "$1" != "$2" ]; then echo 1; else echo 0; fi; }

mkplug() { # <dir>: a plugin copy with the real template trees linked in
  local d=$1 s
  mkdir -p "$d/skills/cleanup/remove-example"
  cp "$RX"/remove-example.sh "$RX"/*.manifest "$d/skills/cleanup/remove-example/"
  for s in nextjs vite-react fastapi nestjs; do
    mkdir -p "$d/skills/scaffold/$s"
    ln -s "$ROOT/skills/scaffold/$s/template" "$d/skills/scaffold/$s/template"
  done
}
PLUG=$T/plugin
mkplug "$PLUG"
SC=$PLUG/skills/cleanup/remove-example/remove-example.sh
xr() { bash "$SC" "$@" 2>&1; echo "rc=$?"; }

# one seeded project per stack, copied for each probe
MASTER=$T/master
for s in nextjs vite-react fastapi nestjs; do
  mkdir -p "$MASTER/$s"
  for p in base stack agents; do
    TC_STACK=$s TC_PART=$p bash "$COPY" "$MASTER/$s" >/dev/null 2>&1 || { echo "FAIL seed $s $p"; exit 1; }
  done
done
sd() { mkdir -p "$2" && cp -Rp "$MASTER/$1/." "$2/"; } # sd <stack> <dir>

# pyrep <file> <old> <new> [nth]: exact replace; fails when old is not found exactly once (nth 0) or at least nth times
pyrep() {
  python3 - "$@" <<'PY'
import sys
f, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
nth = int(sys.argv[4]) if len(sys.argv) > 4 else 0
s = open(f).read()
c = s.count(old)
if c == 0 or (nth == 0 and c != 1) or (nth > c):
    sys.exit(3)
if nth == 0:
    s = s.replace(old, new)
else:
    parts = s.split(old)
    s = old.join(parts[:nth]) + new + old.join(parts[nth:])
open(f, "w").write(s)
PY
}
# mutant <job-dir> <old> <new> [nth]: a plugin copy whose script has one exact replacement; MUT is its script
mutant() {
  local J=$1; shift
  rm -rf "$J/pm"; mkplug "$J/pm"
  MUT=$J/pm/skills/cleanup/remove-example/remove-example.sh
  pyrep "$MUT" "$@" || { echo "FAIL mutant pattern is stale: $1"; return 1; }
}
mutadd() { pyrep "$MUT" "$@" || { echo "FAIL mutant pattern is stale: $1"; return 1; }; }
mx() { bash "$MUT" "$@" 2>&1; echo "rc=$?"; }

# --- hooks
# CAP is the hang-only limit of every wait on a file (in 0.05 s steps, 300 s): the waits end on an event, the cap only stops a
# hung harness, and it says "harness timeout" so it cannot be taken for a result.
CAP=6000
# mkshim <dir> <cmd> <mode> <marker> [skip]: a shim for <cmd>; mode pause (wait for go) or fail (exit 1), on the first match
# after <skip> matches have gone through (default 0).
# A paused shim runs the real command after go and then writes <dir>/done; it gives up when the go file never comes or the
# test directory is gone.
mkshim() {
  local H=$1 cmd=$2 mode=$3 marker=$4 skip=${5:-0} real
  real=$(command -v "$cmd")
  mkdir -p "$H/bin"
  printf '%s\n' '#!/bin/bash' \
    "case \"\$*\" in *\"$marker\"*)" \
    "  if [ ! -e \"$H/fired\" ]; then" \
    "    c=0; if [ -e \"$H/count\" ]; then read -r c <\"$H/count\"; fi" \
    "    c=\$((c + 1)); echo \"\$c\" >\"$H/count\"" \
    "    if [ \"\$c\" -le $skip ]; then exec $real \"\$@\"; fi" \
    "    : >\"$H/fired\"" \
    "    if [ \"$mode\" = fail ]; then exit 1; fi" \
    "    : >\"$H/ready\"" \
    "    n=0" \
    "    while [ ! -e \"$H/go\" ]; do" \
    "      n=\$((n + 1))" \
    "      if [ \"\$n\" -gt $CAP ] || [ ! -d \"$T\" ]; then exit 99; fi" \
    "      /bin/sleep 0.05" \
    "    done" \
    "    $real \"\$@\"; rc=\$?" \
    "    : >\"$H/done\"" \
    "    exit \$rc" \
    "  fi ;;" \
    "esac" \
    "exec $real \"\$@\"" >"$H/bin/$cmd"
  chmod +x "$H/bin/$cmd"
}
PID=
# launch <hook-dir> <script> args...: the script in the background through the launcher, output in <hook-dir>/out
launch() {
  local H=$1 script=$2
  shift 2
  PATH="$H/bin:$PATH" python3 -c 'import os, signal, sys
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(s, signal.SIG_DFL)
os.execv("/bin/bash", ["bash"] + sys.argv[1:])' "$script" "$@" >"$H/out" 2>&1 &
  PID=$!
}
# waitready <hook-dir>: 0 when the shim fired and waits; 1 when the script ended without firing it (an event, no timer);
# 1 with a "harness timeout" line when nothing happened for the whole cap
waitready() {
  local H=$1 i=0
  while [ ! -e "$H/ready" ]; do
    i=$((i + 1))
    if [ "$i" -gt "$CAP" ]; then echo "FAIL harness timeout: waited for the hook in $H"; return 1; fi
    if ! kill -0 "$PID" 2>/dev/null; then return 1; fi
    /bin/sleep 0.05
  done
  return 0
}
# settle <hook-dir>: after the script ended, wait for a paused shim to finish its real command (it writes done)
settle() {
  local H=$1 i=0
  if [ ! -e "$H/ready" ]; then return 0; fi
  while [ ! -e "$H/done" ]; do
    i=$((i + 1))
    if [ "$i" -gt "$CAP" ]; then echo "FAIL harness timeout: the shim in $H never finished"; return 1; fi
    /bin/sleep 0.05
  done
}
RC=
finish() { : >"$1/go"; wait "$PID"; RC=$?; }

# --- groups
PAGE='src/app/dashboard/(overview)/page.tsx'

# a signal during the apply: rolled back, the right exit code, the tree as it was; mutants: no trap, no rollback on stop
g_signal() { # <sig> <code>
  local sig=$1 code=$2 J=$T/j.sig$1 D h H=$T/j.sig$1/h o
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  mkshim "$H" rm pause "src/features/example/"
  launch "$H" "$SC" "$D" --apply
  if ! waitready "$H"; then echo "FAIL $sig: the hook never fired"; finish "$H"; return; fi
  kill -s "$sig" "$PID"
  finish "$H"; o=$(cat "$H/out")
  check "SIG$sig during the apply: exit code" "$code" "$RC"
  contains "SIG$sig: names the signal" "interrupted by SIG$sig" "$o"
  contains "SIG$sig: says it restored every file" "every file was restored" "$o"
  check "SIG$sig: the project is as it was before the run" "$h" "$(treehash "$D")"
  # mutant: the trap for this signal removed
  if mutant "$J" "trap 'on_signal $sig $code' $sig" ":"; then
    rm -rf "$J/p2" "$J/h2"; sd nextjs "$J/p2"
    mkshim "$J/h2" rm pause "src/features/example/"
    launch "$J/h2" "$MUT" "$J/p2" --apply
    if waitready "$J/h2"; then kill -s "$sig" "$PID"; fi
    finish "$J/h2"; settle "$J/h2"
    if [ "$sig" = INT ]; then
      check "mutant without the $sig trap leaves the project half-removed" "1" "$(changed01 "$h" "$(treehash "$J/p2")")"
    else
      # bash runs the EXIT trap on TERM and HUP, so the EXIT rollback still restores the tree; what the signal trap adds is the message and the exit code
      absent "mutant without the $sig trap gives no interrupted message" "interrupted by SIG$sig" "$(cat "$J/h2/out")"
    fi
  fi
  # mutant: the trap runs but the cleanup does not roll back
  if mutant "$J" $'restoring the project" >&2\n    rollback' $'restoring the project" >&2'; then
    rm -rf "$J/p3" "$J/h3"; sd nextjs "$J/p3"
    mkshim "$J/h3" rm pause "src/features/example/"
    launch "$J/h3" "$MUT" "$J/p3" --apply
    if waitready "$J/h3"; then kill -s "$sig" "$PID"; fi
    finish "$J/h3"
    check "mutant that stops without a rollback leaves the project half-removed ($sig)" "1" "$(changed01 "$h" "$(treehash "$J/p3")")"
  fi
}
g_sig_int() { g_signal INT 130; }
g_sig_term() { g_signal TERM 143; }
g_sig_hup() { g_signal HUP 129; }

# a signal with some files already deleted and one moved aside (paused on the compare of the third delete): the whole tree comes
# back, bytes and modes; mutants: no restore of the deleted files, no put-back of the held file
g_sig_nth() { # <sig> <code>
  local sig=$1 code=$2 J=$T/j.nth$1 D h H=$T/j.nth$1/h o MARK=.remove-example.held.
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  # two edits come first, then the deletes: skip 4 compares, pause on the fifth (the third delete)
  mkshim "$H" cmp pause "$MARK" 4
  launch "$H" "$SC" "$D" --apply
  if ! waitready "$H"; then echo "FAIL $sig nth: the hook never fired"; finish "$H"; return; fi
  check "SIG$sig on the third delete: the first delete is already gone" "0" "$(exists01 "$D/src/features/example/api/example-service.ts")"
  kill -s "$sig" "$PID"
  finish "$H"; o=$(cat "$H/out")
  check "SIG$sig on the third delete: exit code" "$code" "$RC"
  contains "SIG$sig on the third delete: says every file was restored" "every file was restored" "$o"
  check "SIG$sig on the third delete: the project is as it was (hash and modes)" "$h" "$(treehash "$D")"
  if mutant "$J" $'if ! cp -p -- "$STAGE/snapdel/$rel" "$ROOT/$rel"; then echo "remove-example: could not restore $rel" >&2; bad=1; fi' ':'; then
    rm -rf "$J/p2" "$J/h2"; sd nextjs "$J/p2"
    mkshim "$J/h2" cmp pause "$MARK" 4
    launch "$J/h2" "$MUT" "$J/p2" --apply
    if waitready "$J/h2"; then kill -s "$sig" "$PID"; fi
    finish "$J/h2"; settle "$J/h2"
    check "mutant without the restore loop leaves the deleted files missing ($sig)" "1" "$(changed01 "$h" "$(treehash "$J/p2")")"
  fi
  if mutant "$J" $'if ! mv -- "$h" "$t"; then echo "remove-example: could not put back $t; the file is at $h" >&2; bad=1; fi' ':'; then
    rm -rf "$J/p3" "$J/h3"; sd nextjs "$J/p3"
    mkshim "$J/h3" cmp pause "$MARK" 4
    launch "$J/h3" "$MUT" "$J/p3" --apply
    if waitready "$J/h3"; then kill -s "$sig" "$PID"; fi
    finish "$J/h3"; settle "$J/h3"
    check "mutant without the put-back of the held file leaves it moved aside ($sig)" "1" "$(changed01 "$h" "$(treehash "$J/p3")")"
  fi
}
g_sig_nth_int() { g_sig_nth INT 130; }
g_sig_nth_term() { g_sig_nth TERM 143; }
g_sig_nth_hup() { g_sig_nth HUP 129; }

# launchpipe <hook-dir> <script> args...: as launch, with stderr a pipe nobody reads (every write to it fails) and SIGPIPE at its default
launchpipe() {
  local H=$1 script=$2
  shift 2
  PATH="$H/bin:$PATH" python3 -c 'import os, signal, sys
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGPIPE):
    signal.signal(s, signal.SIG_DFL)
r, w = os.pipe()
os.close(r)
os.dup2(w, 2)
os.close(w)
os.execv("/bin/bash", ["bash"] + sys.argv[1:])' "$script" "$@" >"$H/out" &
  PID=$!
}

# a closed stderr must not stop the rollback: a delete fails midway while every write to stderr fails
g_pipe() {
  local J=$T/j.pipe D h H=$T/j.pipe/h
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  mkshim "$H" rm fail "src/features/example/"
  launchpipe "$H" "$SC" "$D" --apply
  finish "$H"
  check "a failed delete with a closed stderr: exit 1" "1" "$RC"
  check "a failed delete with a closed stderr: the project is as it was (hash and modes)" "$h" "$(treehash "$D")"
  if mutant "$J" $'APPLYING=1\ntrap \'\' PIPE\n' $'APPLYING=1\n' &&
     mutadd $'  trap \'\' INT TERM HUP PIPE\n  if [ "$APPLYING" -eq 1 ]' $'  trap \'\' INT TERM HUP\n  if [ "$APPLYING" -eq 1 ]' &&
     mutadd $'  trap \'\' INT TERM HUP PIPE\n  ROLLED=1' $'  trap \'\' INT TERM HUP\n  ROLLED=1'; then
    rm -rf "$J/p2" "$J/h2"; sd nextjs "$J/p2"
    mkshim "$J/h2" rm fail "src/features/example/"
    launchpipe "$J/h2" "$MUT" "$J/p2" --apply
    finish "$J/h2"
    check "mutant that does not mask SIGPIPE dies on the closed stderr and leaves the project half-done" "1" "$(changed01 "$h" "$(treehash "$J/p2")")"
  fi
}

# a signal before the apply changes nothing (the hook waits during the checks)
g_sig_early() {
  local J=$T/j.early D h H=$T/j.early/h
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  mkshim "$H" cp pause "snapdel/src/features/example/index.ts"
  launch "$H" "$SC" "$D" --apply
  if ! waitready "$H"; then echo "FAIL early: the hook never fired"; finish "$H"; return; fi
  kill -s TERM "$PID"
  finish "$H"
  check "SIGTERM before the first write: exit code" "143" "$RC"
  check "SIGTERM before the first write: nothing changed" "$h" "$(treehash "$D")"
  absent "SIGTERM before the first write: no rollback talk" "restoring the project" "$(cat "$H/out")"
}

# a rollback that cannot finish keeps the copies and says so
g_sig_keep() {
  local J=$T/j.keep D H=$T/j.keep/h o stage
  if [ "$NOTROOT" -ne 1 ]; then echo "skip rollback-incomplete probe: running as root"; return; fi
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"
  mkshim "$H" rm pause "src/features/example/"
  launch "$H" "$SC" "$D" --apply
  if ! waitready "$H"; then echo "FAIL keep: the hook never fired"; finish "$H"; return; fi
  chmod a-w "$D/src/app/dashboard/(overview)"
  kill -s TERM "$PID"
  finish "$H"; o=$(cat "$H/out")
  chmod u+w "$D/src/app/dashboard/(overview)"
  contains "a rollback that cannot restore: says ROLLBACK INCOMPLETE" "ROLLBACK INCOMPLETE" "$o"
  check "a rollback that cannot restore: non-zero exit" "1" "$(changed01 0 "$RC")"
  stage=${o#*kept in }; stage=${stage%%$'\n'*}
  check "a rollback that cannot restore: the copies are kept" "1" "$(exists01 "$stage/snapedit.1")"
  rm -rf "$stage"
  if mutant "$J" $'    KEEP_STAGE=1\n    echo "remove-example: ROLLBACK' $'    echo "remove-example: ROLLBACK'; then
    rm -rf "$J/p2" "$J/h2"; sd nextjs "$J/p2"
    mkshim "$J/h2" rm pause "src/features/example/"
    launch "$J/h2" "$MUT" "$J/p2" --apply
    if waitready "$J/h2"; then chmod a-w "$J/p2/src/app/dashboard/(overview)"; kill -s TERM "$PID"; fi
    finish "$J/h2"
    chmod u+w "$J/p2/src/app/dashboard/(overview)"
    o=$(cat "$J/h2/out"); stage=${o#*kept in }; stage=${stage%%$'\n'*}
    check "mutant that does not keep the copies loses them when the rollback fails" "0" "$(exists01 "$stage/snapedit.1")"
    rm -rf "$stage"
  fi
}

# a delete that fails midway: rolled back (mutant: no rollback)
g_rm_fail() {
  local J=$T/j.rmfail D h H=$T/j.rmfail/h o
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  mkshim "$H" rm fail "src/features/example/"
  launch "$H" "$SC" "$D" --apply
  finish "$H"; o=$(cat "$H/out")
  check "a delete that fails: exit 1" "1" "$RC"
  contains "a delete that fails: says which file" "cannot delete" "$o"
  check "a delete that fails: the project is as it was" "$h" "$(treehash "$D")"
  if mutant "$J" $'  echo "remove-example: $1" >&2\n  rollback\n  exit 1' $'  echo "remove-example: $1" >&2\n  exit 1' && mutadd $'restoring the project" >&2\n    rollback' $'restoring the project" >&2'; then
    rm -rf "$J/p2" "$J/h2"; sd nextjs "$J/p2"
    mkshim "$J/h2" rm fail "src/features/example/"
    launch "$J/h2" "$MUT" "$J/p2" --apply
    finish "$J/h2"
    check "mutant without any rollback (fail_apply and the exit trap) leaves the project half-done" "1" "$(changed01 "$h" "$(treehash "$J/p2")")"
  fi
}

# an edit target that stops being a regular file between the staging and the apply
g_swap() { # <kind: link|dir>
  local kind=$1 J=$T/j.swap$1 D h H=$T/j.swap$1/h o routes
  mkdir -p "$J"; D=$J/p; sd fastapi "$D"
  routes=$(cat "$D/src/api/routes.py")
  mkshim "$H" cat pause "/out.1"
  launch "$H" "$SC" "$D" --apply
  if ! waitready "$H"; then echo "FAIL swap $kind: the hook never fired"; finish "$H"; return; fi
  rm -f "$D/src/api/tags.py"
  if [ "$kind" = link ]; then ln -s routes.py "$D/src/api/tags.py"; else mkdir "$D/src/api/tags.py"; fi
  finish "$H"; o=$(cat "$H/out")
  check "an edit target that became a $kind: exit 1" "1" "$RC"
  contains "an edit target that became a $kind: says so" "is no longer a regular file" "$o"
  check "an edit target that became a $kind: the first edit was rolled back" "$routes" "$(cat "$D/src/api/routes.py")"
  if mutant "$J" $'if [ -L "$HELD" ] || [ ! -f "$HELD" ]; then fail_apply "$label is no longer a regular file"; fi' ':'; then
    rm -rf "$J/p2" "$J/h2"; sd fastapi "$J/p2"
    mkshim "$J/h2" cat pause "/out.1"
    launch "$J/h2" "$MUT" "$J/p2" --apply
    if waitready "$J/h2"; then
      rm -f "$J/p2/src/api/tags.py"
      if [ "$kind" = link ]; then ln -s routes.py "$J/p2/src/api/tags.py"; else mkdir "$J/p2/src/api/tags.py"; fi
    fi
    finish "$J/h2"
    absent "mutant without the regular-file guard does not refuse the $kind" "is no longer a regular file" "$(cat "$J/h2/out")"
  fi
}
g_swap_link() { g_swap link; }
g_swap_dir() { g_swap dir; }

# a file to delete that changes after the checks (forced or not): it is compared again when it is moved aside, refused, put back
g_mid_delete() {
  local J=$T/j.middel D h H=$T/j.middel/h o
  local F=src/features/example/index.ts
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"
  # the file is changed after the early re-check and before it is moved aside
  mkshim "$H" mv pause "$F"
  launch "$H" "$SC" "$D" --apply
  if ! waitready "$H"; then echo "FAIL mid delete: the hook never fired"; finish "$H"; return; fi
  printf '\n// mine\n' >>"$D/$F"
  # expected: the seeded project with the user's change (earlier files are already deleted at the pause)
  rm -rf "$J/e"; sd nextjs "$J/e"; printf '\n// mine\n' >>"$J/e/$F"; h=$(treehash "$J/e")
  finish "$H"; o=$(cat "$H/out")
  check "a file changed after the checks: exit 1" "1" "$RC"
  contains "a file changed after the checks: says it changed" "changed while the script ran" "$o"
  contains "a file changed after the checks: says it was restored" "every file was restored" "$o"
  check "a file changed after the checks: the project is as it was, with the user's change (hash and modes)" "$h" "$(treehash "$D")"
  # control: the same pause with no change applies
  rm -rf "$J/c" "$J/hc"; sd nextjs "$J/c"
  mkshim "$J/hc" mv pause "$F"
  launch "$J/hc" "$SC" "$J/c" --apply
  if waitready "$J/hc"; then :; fi
  finish "$J/hc"
  check "control: the same pause with no change applies" "0" "$RC"
  check "control: the example directory is gone" "0" "$(exists01 "$J/c/src/features/example")"
  # mutant: the compare after the move removed
  if mutant "$J" $'if ! cmp -s -- "$HELD" "$copy"; then fail_apply "$label changed while the script ran; it was put back"; fi' ':'; then
    rm -rf "$J/p2" "$J/h2"; sd nextjs "$J/p2"
    mkshim "$J/h2" mv pause "$F"
    launch "$J/h2" "$MUT" "$J/p2" --apply
    if waitready "$J/h2"; then printf '\n// mine\n' >>"$J/p2/$F"; fi
    finish "$J/h2"
    check "mutant without the compare after the move deletes the file the user changed" "0" "$(exists01 "$J/p2/$F")"
  fi
  # a forced file gets the same re-check: it is forced as it was found, a later change is refused
  rm -rf "$J/p3" "$J/h3"; sd nextjs "$J/p3"
  printf '\n// first\n' >>"$J/p3/$F"
  mkshim "$J/h3" mv pause "$F"
  launch "$J/h3" "$SC" "$J/p3" --apply --force "$F"
  if waitready "$J/h3"; then printf '\n// second\n' >>"$J/p3/$F"; fi
  rm -rf "$J/e"; sd nextjs "$J/e"; printf '\n// first\n\n// second\n' >>"$J/e/$F"; h=$(treehash "$J/e")
  finish "$J/h3"; o=$(cat "$J/h3/out")
  check "a forced file changed after the checks: exit 1" "1" "$RC"
  contains "a forced file changed after the checks: says it changed" "changed while the script ran" "$o"
  check "a forced file changed after the checks: the project is as it was (hash and modes)" "$h" "$(treehash "$J/p3")"
  # control: a forced file that stays as it was found is applied
  rm -rf "$J/p4" "$J/h4"; sd nextjs "$J/p4"
  printf '\n// first\n' >>"$J/p4/$F"
  mkshim "$J/h4" mv pause "$F"
  launch "$J/h4" "$SC" "$J/p4" --apply --force "$F"
  if waitready "$J/h4"; then :; fi
  finish "$J/h4"
  check "control: a forced file that does not change is applied" "0" "$RC"
  check "control: the forced file is gone" "0" "$(exists01 "$J/p4/$F")"
  # mutant: no compare after the move: the forced file changed after the checks is deleted all the same
  if mutant "$J" $'if ! cmp -s -- "$HELD" "$copy"; then fail_apply "$label changed while the script ran; it was put back"; fi' ':'; then
    rm -rf "$J/p5" "$J/h5"; sd nextjs "$J/p5"
    printf '\n// first\n' >>"$J/p5/$F"
    mkshim "$J/h5" mv pause "$F"
    launch "$J/h5" "$MUT" "$J/p5" --apply --force "$F"
    if waitready "$J/h5"; then printf '\n// second\n' >>"$J/p5/$F"; fi
    finish "$J/h5"
    check "mutant without the compare deletes a forced file the user changed again" "0" "$(exists01 "$J/p5/$F")"
  fi
  # the early re-check: a file changed after its copy, before the apply begins, stops the run before anything is written
  rm -rf "$J/p6" "$J/h6"; sd nextjs "$J/p6"
  mkshim "$J/h6" cp pause "snapdel/src/features/example/types.ts"
  launch "$J/h6" "$SC" "$J/p6" --apply
  if waitready "$J/h6"; then printf '\n// mine\n' >>"$J/p6/$F"; fi
  h=$(treehash "$J/p6")
  finish "$J/h6"; o=$(cat "$J/h6/out")
  check "a file changed before the apply starts: exit 1" "1" "$RC"
  contains "a file changed before the apply starts: nothing was changed" "changed while the script ran; nothing was changed" "$o"
  absent "a file changed before the apply starts: no rollback was needed" "restoring the project" "$o"
  check "a file changed before the apply starts: the project is as it was (hash and modes)" "$h" "$(treehash "$J/p6")"
  if mutant "$J" $'if ! cmp -s -- "$STAGE/snapdel/$rel" "$ROOT/$rel"; then die "$rel changed while the script ran; nothing was changed"; fi' ':'; then
    rm -rf "$J/p7" "$J/h7"; sd nextjs "$J/p7"
    mkshim "$J/h7" cp pause "snapdel/src/features/example/types.ts"
    launch "$J/h7" "$MUT" "$J/p7" --apply
    if waitready "$J/h7"; then printf '\n// mine\n' >>"$J/p7/$F"; fi
    finish "$J/h7"
    absent "mutant without the early re-check no longer stops before the apply" "changed while the script ran; nothing was changed" "$(cat "$J/h7/out")"
  fi
}

# a copy that cannot be taken
g_cp_fail() {
  local J=$T/j.cpfail D h H o
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  H=$J/h1; mkshim "$H" cp fail "snapedit"
  launch "$H" "$SC" "$D" --apply; finish "$H"; o=$(cat "$H/out")
  check "an edit file that cannot be copied: exit 1" "1" "$RC"
  contains "an edit file that cannot be copied: says so" "cannot be copied for the rollback" "$o"
  check "an edit file that cannot be copied: nothing written" "$h" "$(treehash "$D")"
  if mutant "$J" $'if ! cp -p -- "$ROOT/$file" "$snap"; then block "$file cannot be copied for the rollback"; continue; fi' $'cp -p -- "$ROOT/$file" "$snap"'; then
    rm -rf "$J/m1"; H=$J/hm1; mkshim "$H" cp fail "snapedit"
    sd nextjs "$J/m1"
    launch "$H" "$MUT" "$J/m1" --apply; finish "$H"
    absent "mutant without the copy check does not say it" "cannot be copied for the rollback" "$(cat "$H/out")"
  fi
  rm -rf "$J/p2"; sd nextjs "$J/p2"; h=$(treehash "$J/p2")
  H=$J/h2; mkshim "$H" cp fail "snapdel/"
  launch "$H" "$SC" "$J/p2" --apply; finish "$H"; o=$(cat "$H/out")
  check "a file to delete that cannot be copied: exit 1" "1" "$RC"
  contains "a file to delete that cannot be copied: says so" "cannot be copied for the rollback" "$o"
  check "a file to delete that cannot be copied: nothing changed" "$h" "$(treehash "$J/p2")"
  if mutant "$J" $'if ! snap_delete "$rel"; then block "$rel cannot be copied for the rollback"; continue; fi' $'snap_delete "$rel"'; then
    rm -rf "$J/m2"; sd nextjs "$J/m2"; H=$J/hm2; mkshim "$H" cp fail "snapdel/"
    launch "$H" "$MUT" "$J/m2" --apply; finish "$H"
    absent "mutant without the delete-copy check does not say it" "cannot be copied for the rollback" "$(cat "$H/out")"
  fi
}

# the replace is a rename: a hard link to the edited file keeps the old bytes (mutant: an in-place write changes them)
g_inode() {
  local J=$T/j.inode D old
  mkdir -p "$J"; D=$J/p; sd fastapi "$D"
  old=$(cat "$D/src/api/routes.py")
  ln "$D/src/api/routes.py" "$J/link.py"
  xr "$D" --apply >/dev/null
  check "an edited file is replaced by a rename: a hard link keeps the old bytes" "$old" "$(cat "$J/link.py")"
  if mutant "$J" $'  take "$target" "$snap"\n  if ! mv -- "$tmp" "$target"; then' $'  HELD=$target.none\n  if ! cat -- "$tmp" >"$target"; then'; then
    rm -rf "$J/p2" "$J/link2.py"; sd fastapi "$J/p2"; ln "$J/p2/src/api/routes.py" "$J/link2.py"
    mx "$J/p2" --apply >/dev/null
    check "mutant with an in-place write changes the bytes the hard link sees" "1" "$(changed01 "$old" "$(cat "$J/link2.py")")"
  fi
}

# an empty example directory that cannot be removed: rolled back
g_rmdir() {
  local J=$T/j.rmdir D h o
  if [ "$NOTROOT" -ne 1 ]; then echo "skip rmdir probe: running as root"; return; fi
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  chmod a-w "$D/src/features"
  o=$(xr "$D" --apply)
  chmod u+w "$D/src/features"
  contains "a directory that cannot be removed: exit 1" "rc=1" "$o"
  contains "a directory that cannot be removed: says which" "cannot remove the directory" "$o"
  check "a directory that cannot be removed: the project is as it was" "$h" "$(treehash "$D")"
  if mutant "$J" $'if ! rmdir -- "$d"; then fail_apply "cannot remove the directory ${d#"$ROOT"/}"; fi' $'rmdir -- "$d"'; then
    rm -rf "$J/p2"; sd nextjs "$J/p2"; chmod a-w "$J/p2/src/features"
    o=$(mx "$J/p2" --apply)
    chmod u+w "$J/p2/src/features"
    absent "mutant without the rmdir check does not say it" "cannot remove the directory" "$o"
  fi
}

# an unreadable directory inside the example: refused; each of the four listings is shown to fire
g_unreadable() {
  local J=$T/j.unread D h o k m
  if [ "$NOTROOT" -ne 1 ]; then echo "skip unreadable-directory probes: running as root"; return; fi
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"
  mkdir "$D/src/features/example/sub"
  h=$(treehash "$D")
  chmod 000 "$D/src/features/example/sub"
  o=$(xr "$D" --apply)
  chmod 755 "$D/src/features/example/sub"
  contains "an unreadable directory in the example: refused" "rc=1" "$o"
  contains "an unreadable directory in the example: says why" "cannot be listed (an unreadable directory inside it)" "$o"
  check "an unreadable directory in the example: nothing written" "$h" "$(treehash "$D")"
  o=$(xr "$D" --apply)
  contains "control: the same directory readable applies" "remove-example: applied" "$o"
  for k in 2 3 4; do
    if mutant "$J" $'then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi' 'then :; fi' 1; then
      m=2
      while [ "$m" -lt "$k" ]; do mutadd $'then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi' 'then :; fi' 1; m=$((m + 1)); done
      rm -rf "$J/q$k"; sd nextjs "$J/q$k"; mkdir "$J/q$k/src/features/example/sub"
      chmod 000 "$J/q$k/src/features/example/sub"
      # guards 1..k-1 are gone: guard k is the one that fires
      o=$(mx "$J/q$k" --apply)
      chmod 755 "$J/q$k/src/features/example/sub"
      contains "with listing guards 1 to $((k - 1)) removed, guard $k refuses" "cannot be listed" "$o"
    fi
  done
  # all four removed: the message is gone
  if mutant "$J" $'then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi' 'then :; fi' 1; then
    mutadd $'then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi' 'then :; fi' 1
    mutadd $'then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi' 'then :; fi' 1
    mutadd $'then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi' 'then :; fi' 1
    rm -rf "$J/q5"; sd nextjs "$J/q5"; mkdir "$J/q5/src/features/example/sub"; chmod 000 "$J/q5/src/features/example/sub"
    o=$(mx "$J/q5" --apply)
    chmod 755 "$J/q5/src/features/example/sub"
    absent "with all four listing guards removed the refusal is gone" "cannot be listed" "$o"
  fi
}

# a FIFO or a socket as a delete root; an edit target that is a directory
g_special_root() {
  local J=$T/j.special D h o kind
  mkdir -p "$J"
  for kind in fifo socket; do
    rm -rf "${J:?}/$kind" "$J/pl"; D=$J/$kind; sd nextjs "$D"
    mkplug "$J/pl"
    printf 'delete\t%s\n' "$PAGE" >"$J/pl/skills/cleanup/remove-example/nextjs.manifest"
    rm "$D/$PAGE"
    if [ "$kind" = fifo ]; then mkfifo "$D/$PAGE"; else (cd "$D/${PAGE%/*}" && python3 -c 'import socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "${PAGE##*/}") 2>/dev/null || { echo "skip socket probe: cannot bind"; continue; }; fi
    h=$(treehash "$D")
    o=$(bash "$J/pl/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
    contains "a $kind as the delete root: refused" "rc=1" "$o"
    contains "a $kind as the delete root: says why" "is not a regular file or directory" "$o"
    check "a $kind as the delete root: nothing written" "$h" "$(treehash "$D")"
    if [ "$kind" = fifo ] && mutant "$J" $'    block "$p is not a regular file or directory"; continue' '    :'; then
      cp "$J/pl/skills/cleanup/remove-example/nextjs.manifest" "$J/pm/skills/cleanup/remove-example/nextjs.manifest"
      o=$(mx "$D" --apply)
      absent "mutant without the special-root check does not say it" "is not a regular file or directory" "$o"
    fi
  done
  # an edit target that is a directory
  rm -rf "$J/ed"; D=$J/ed; sd nextjs "$D"; rm "$D/$PAGE"; mkdir "$D/$PAGE"; h=$(treehash "$D")
  o=$(xr "$D" --apply)
  contains "an edit target that is a directory: refused" "rc=1" "$o"
  contains "an edit target that is a directory: says why" "to edit is not a regular file" "$o"
  check "an edit target that is a directory: nothing written" "$h" "$(treehash "$D")"
  if mutant "$J" $'then block "$file to edit is not a regular file"; continue; fi' 'then :; fi'; then
    o=$(mx "$D" --apply)
    absent "mutant without the regular-file check does not say it" "to edit is not a regular file" "$o"
  fi
}

# a file with no final newline, an edit file that cannot be read
g_edit_refusals() {
  local J=$T/j.editref D h o
  mkdir -p "$J"; D=$J/p; sd fastapi "$D"
  printf '%s' "$(cat "$D/src/api/tags.py")" >"$D/src/api/tags.py"
  h=$(treehash "$D")
  o=$(xr "$D" --apply)
  contains "an edit file with no final newline: refused" "rc=1" "$o"
  contains "an edit file with no final newline: says why" "has no final newline" "$o"
  check "an edit file with no final newline: nothing written" "$h" "$(treehash "$D")"
  if mutant "$J" $'if [ -s "$snap" ] && [ -n "$(tail -c1 "$snap")" ]; then block "$file has no final newline"; continue; fi' ':'; then
    absent "mutant without the final-newline check does not say it" "has no final newline" "$(mx "$D" --apply)"
  fi
}

# the stack read from the marker on line 1 only, from an allow-list
g_marker() {
  local J=$T/j.marker D o
  mkdir -p "$J"
  D=$J/second; sd nextjs "$D"
  { echo '# Project'; cat "$D/AGENTS.md"; } >"$D/AGENTS.new"; mv "$D/AGENTS.new" "$D/AGENTS.md"
  o=$(xr "$D")
  contains "a marker on line 2: refused" "no templateCentral marker" "$o"
  if mutant "$J" $'IFS= read -r line <"$AGENTS" || [ -n "$line" ] || line=' "line=\$(grep -m1 '^<!-- templateCentral: ' \"\$AGENTS\")"; then
    absent "mutant that searches below line 1 accepts the marker on line 2" "no templateCentral marker" "$(mx "$D")"
  fi
  D=$J/prose; sd nextjs "$D"
  { echo 'see <!-- templateCentral: nextjs@6.0.0 --> for the stack'; cat "$D/AGENTS.md"; } >"$D/AGENTS.new"; mv "$D/AGENTS.new" "$D/AGENTS.md"
  contains "a marker quoted in prose on line 1: refused" "no templateCentral marker" "$(xr "$D")"
  D=$J/evil; sd nextjs "$D"
  { echo '<!-- templateCentral: ../x@1 -->'; sed '1d' "$D/AGENTS.md"; } >"$D/AGENTS.new"; mv "$D/AGENTS.new" "$D/AGENTS.md"
  o=$(xr "$D")
  contains "a marker stack of ../x: refused" "naming a stack" "$o"
  if mutant "$J" $'case "$STACK" in nestjs | nextjs | vite-react | fastapi) ;; *) die "AGENTS.md has no templateCentral marker naming a stack on line 1: run templatecentral:migrate first" ;; esac' ':'; then
    absent "mutant without the stack allow-list lets ../x through" "naming a stack" "$(mx "$D")"
  fi
  o=$(xr /)
  contains "the project path /: refused" "refusing to run on /" "$o"
  if mutant "$J" $'[ "$ROOT" != / ] || die "refusing to run on /"' ':'; then
    absent "mutant without the / check goes on" "refusing to run on /" "$(mx /)"
  fi
}

# the plugin version NOTE and the stderr/stdout split
g_streams() {
  local J=$T/j.streams D so se
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"
  printf '\n// mine\n' >>"$D/src/features/example/index.ts"
  so=$(bash "$SC" "$D" --apply 2>/dev/null); se=$(bash "$SC" "$D" --apply 2>&1 >/dev/null)
  absent "a blocker: stdout holds no BLOCK line" "BLOCK" "$so"
  contains "a blocker: stderr holds the BLOCK line" "BLOCK  src/features/example/index.ts differs" "$se"
  contains "a blocker: stderr holds the summary" "1 blocker(s); nothing was changed" "$se"
  contains "an older marker version: stderr holds the NOTE" "NOTE   the project marker says templateCentral 6.0.0, this plugin is unknown" "$se"
  absent "an older marker version: stdout holds no NOTE" "NOTE" "$so"
  mkplug "$J/same"; mkdir -p "$J/same/.claude-plugin"; printf '{"version": "6.0.0"}\n' >"$J/same/.claude-plugin/plugin.json"
  se=$(bash "$J/same/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1 >/dev/null)
  absent "the same marker and plugin version: no NOTE" "NOTE" "$se"
  if mutant "$J" $'if [ "$VERSION_NOTE" -eq 1 ] && [ "$MARK_VER" != "$PLUGIN_VER" ]; then' $'if [ "$VERSION_NOTE" -eq 1 ]; then'; then
    cp -R "$J/same/.claude-plugin" "$J/pm/"
    se=$(bash "$MUT" "$D" --apply 2>&1 >/dev/null)
    contains "mutant without the version compare prints the NOTE for the same version" "NOTE" "$se"
  fi
  if mutant "$J" $'block() { echo "BLOCK  $1" >&2;' $'block() { echo "BLOCK  $1";'; then
    so=$(bash "$MUT" "$D" --apply 2>/dev/null)
    contains "mutant with BLOCK on stdout shows it there" "BLOCK" "$so"
  fi
  # a symlinked edit file is a BLOCK on stderr as well
  rm -rf "$J/p2"; sd nextjs "$J/p2"; mv "$J/p2/$PAGE" "$J/page.real"; ln -s "$J/page.real" "$J/p2/$PAGE"
  so=$(bash "$SC" "$J/p2" --apply 2>/dev/null)
  absent "a symlinked edit file: stdout holds no BLOCK line" "BLOCK" "$so"
}

# usage errors
g_usage() {
  local J=$T/j.usage D
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"
  check "usage: --force with an empty path" "2" "$(bash "$SC" "$D" --force '' >/dev/null 2>&1; echo $?)"
  check "usage: --force with a newline in the path" "2" "$(bash "$SC" "$D" --force "a${NL}b" >/dev/null 2>&1; echo $?)"
  check "usage: two project arguments" "2" "$(bash "$SC" "$D" "$D" >/dev/null 2>&1; echo $?)"
  check "usage: an empty project argument" "2" "$(bash "$SC" '' >/dev/null 2>&1; echo $?)"
  check "control: a project and --apply-less run is fine" "0" "$(bash "$SC" "$D" >/dev/null 2>&1; echo $?)"
  if mutant "$J" "case \"\$1\" in '' | *\"\$NL\"*) usage ;; esac" ':'; then
    check "mutant without the empty/newline --force check accepts them" "0" "$(bash "$MUT" "$D" --force '' >/dev/null 2>&1; echo $?)"
  fi
  if mutant "$J" $'if [ -n "$PROJ" ]; then usage; fi' ':'; then
    check "mutant without the two-project check accepts two" "0" "$(bash "$MUT" "$D" "$D" >/dev/null 2>&1; echo $?)"
  fi
  # a project path with a newline
  mkdir -p "$J/a${NL}b"; sd nextjs "$J/a${NL}b/p"
  contains "a project path with a newline: refused" "holds a newline" "$(xr "$J/a${NL}b/p")"
  if mutant "$J" $'case "$ROOT" in *"$NL"*) die "the project path holds a newline" ;; esac' ':'; then
    absent "mutant without the newline check does not say it" "holds a newline" "$(mx "$J/a${NL}b/p")"
  fi
}

# a CDPATH must not change which project is meant
g_cdpath() {
  local J=$T/j.cdpath o
  mkdir -p "$J/cwd" "$J/decoy/proj"
  sd nextjs "$J/cwd/proj"
  o=$(cd "$J/cwd" && CDPATH="$J/decoy:" bash "$SC" proj 2>&1; echo "rc=$?")
  contains "CDPATH holding another proj: the project in the cwd is used" "dry run: nothing was changed" "$o"
  if mutant "$J" $'set -u\nunset CDPATH' 'set -u'; then
    o=$(cd "$J/cwd" && CDPATH="$J/decoy:" bash "$MUT" proj 2>&1; echo "rc=$?")
    absent "mutant without unset CDPATH no longer reaches the project in the cwd" "dry run: nothing was changed" "$o"
  fi
}

# --force paths: each unclean form refused, each pattern of safe_rel shown, a symlink component refused
g_force_paths() {
  local J=$T/j.force D p o old new
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"
  ln -s "$D/src/features" "$D/featlink"
  for p in "src//features/example" "src/./features/example" "src/../src/features/example" "src/features/example/" "featlink/example"; do
    o=$(xr "$D" --apply --force "$p")
    contains "--force $p: refused" "outside the project, unclean or has a symlink" "$o"
  done
  printf '\n// mine\n' >>"$D/src/features/example/index.ts"
  o=$(xr "$D" --apply --force src/features/example)
  contains "control: a clean --force directory applies" "remove-example: applied" "$o"
  # one pattern removed at a time
  old=$'case "/$p/" in */../* | */./* | *//*) return 1 ;; esac'
  rm -rf "$J/m"; mkdir -p "$J/m"
  new1=$'case "/$p/" in */./* | *//*) return 1 ;; esac'
  new2=$'case "/$p/" in */../* | *//*) return 1 ;; esac'
  new3=$'case "/$p/" in */../* | */./*) return 1 ;; esac'
  rm -rf "$J/pa"; sd nextjs "$J/pa"; ln -s "$J/pa/src/features" "$J/pa/featlink"
  if mutant "$J" "$old" "$new1"; then
    absent "mutant without the .. pattern lets src/../x through" "unclean" "$(mx "$J/pa" --force 'src/../src/features/example')"
  fi
  if mutant "$J" "$old" "$new2"; then
    absent "mutant without the . pattern lets src/./x through" "unclean" "$(mx "$J/pa" --force 'src/./features/example')"
  fi
  if mutant "$J" "$old" "$new3"; then
    absent "mutant without the // pattern lets src//x through" "unclean" "$(mx "$J/pa" --force 'src//features/example')"
    absent "mutant without the // pattern lets dir/ through" "unclean" "$(mx "$J/pa" --force 'src/features/example/')"
  fi
  if mutant "$J" $'if [ -L "$acc" ]; then return 1; fi' ':'; then
    absent "mutant without the symlink check lets a symlink component through" "unclean" "$(mx "$J/pa" --force 'featlink/example')"
  fi
}

# crafted manifests: each bad row refuses (nothing is written); the mutant lacking the clause lets it through
# mrow <name> <manifest> <expect> [<old> <new>]
mrow() {
  local name=$1 rows=$2 expect=$3 old=${4:-} new=${5:-} J=$T/j.man.$$.$RANDOM D h o
  mkdir -p "$J"; D=$J/p; sd nextjs "$D"; h=$(treehash "$D")
  mkplug "$J/pl"
  printf '%b' "$rows" >"$J/pl/skills/cleanup/remove-example/nextjs.manifest"
  o=$(bash "$J/pl/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
  contains "$name: refused" "rc=1" "$o"
  contains "$name: says why" "$expect" "$o"
  check "$name: nothing written" "$h" "$(treehash "$D")"
  if [ -n "$old" ] && mutant "$J" "$old" "$new"; then
    cp "$J/pl/skills/cleanup/remove-example/nextjs.manifest" "$J/pm/skills/cleanup/remove-example/nextjs.manifest"
    o=$(bash "$MUT" "$D" 2>&1)
    absent "$name: the mutant without the clause no longer says it" "$expect" "$o"
  fi
  rm -rf "$J"
}
g_manifest_a() {
  mrow "manifest: a repeated delete path" 'delete\tsrc/features/example\ndelete\tsrc/features/example\n' "repeats or nests" \
    'if (dp[i] == dp[j] || index(dp[i], dp[j] "/") == 1 || index(dp[j], dp[i] "/") == 1)' 'if (index(dp[i], dp[j] "/") == 1 || index(dp[j], dp[i] "/") == 1)'
  mrow "manifest: a delete path nested in an earlier one" 'delete\tsrc/features/example\ndelete\tsrc/features/example/index.ts\n' "repeats or nests" \
    'if (dp[i] == dp[j] || index(dp[i], dp[j] "/") == 1 || index(dp[j], dp[i] "/") == 1)' 'if (dp[i] == dp[j] || index(dp[i], dp[j] "/") == 1)'
  mrow "manifest: a delete path that contains an earlier one" 'delete\tsrc/features/example/index.ts\ndelete\tsrc/features/example\n' "repeats or nests" \
    'if (dp[i] == dp[j] || index(dp[i], dp[j] "/") == 1 || index(dp[j], dp[i] "/") == 1)' 'if (dp[i] == dp[j] || index(dp[j], dp[i] "/") == 1)'
  mrow "manifest: an edit of a deleted file" 'delete\tsrc/features/example/index.ts\nrmline\tsrc/features/example/index.ts\tx\t-\n' "which the delete row" \
    'if (ep[i] == dp[j] || index(ep[i], dp[j] "/") == 1)' 'if (index(ep[i], dp[j] "/") == 1)'
  mrow "manifest: an edit under a deleted directory" 'delete\tsrc/features/example\nrmline\tsrc/features/example/index.ts\tx\t-\n' "which the delete row" \
    'if (ep[i] == dp[j] || index(ep[i], dp[j] "/") == 1)' 'if (ep[i] == dp[j])'
  mrow "manifest: a CR in a row" 'delete\tsrc/features/example\r\n' "carriage return" \
    '  /\r/ { print "line " NR ": carriage return"; next }' ''
}
g_manifest_b() {
  mrow "manifest: a delete row with an extra column" 'delete\tsrc/features/example\textra\n' "malformed row" \
    $'if (NF != 2 || $2 == "")' $'if ($2 == "")'
  mrow "manifest: an rmline with an empty line field" 'rmline\tsrc/a.ts\t\t-\n' "malformed row" \
    $'t == "rmline"  { if (NF != 4 || $2 == "" || $3 == "" ||' $'t == "rmline"  { if (NF != 4 || $2 == "" ||'
  mrow "manifest: an rmblock with an empty first line" 'rmblock\tsrc/a.ts\t2\t\tlast\t-\n' "malformed row" \
    $'$3 !~ /^[1-9][0-9]*$/ || $4 == "" ||' $'$3 !~ /^[1-9][0-9]*$/ ||'
  mrow "manifest: an rmblock with an empty last line" 'rmblock\tsrc/a.ts\t2\tfirst\t\t-\n' "malformed row" \
    $'|| $5 == "" || $6 !~' $'|| $6 !~'
  mrow "manifest: an rmblock with a count that is not a number" 'rmblock\tsrc/a.ts\tx\tfirst\tlast\t-\n' "malformed row" \
    $'|| $3 !~ /^[1-9][0-9]*$/' ''
}

JOBS="sig_int sig_term sig_hup sig_nth_int sig_nth_term sig_nth_hup pipe sig_early sig_keep rm_fail swap_link swap_dir mid_delete cp_fail inode rmdir unreadable special_root edit_refusals marker streams usage cdpath force_paths manifest_a manifest_b"
n=0
for j in $JOBS; do
  ( "g_$j"; echo "job $j done" ) >"$T/o.$j" 2>&1 &
  n=$((n + 1))
  if [ $((n % 4)) -eq 0 ]; then wait; fi
done
wait
fails=0
oks=0
for j in $JOBS; do
  cat "$T/o.$j"
  if ! grep -q "^job $j done\$" "$T/o.$j"; then echo "FAIL group $j did not finish"; fails=$((fails + 1)); fi
  fails=$((fails + $(grep -c '^FAIL' "$T/o.$j")))
  oks=$((oks + $(grep -c '^ok ' "$T/o.$j")))
done
echo "$oks ok, $fails failed"
if [ "$fails" -ne 0 ]; then echo "remove-example edge tests FAILED"; exit 1; fi
echo "remove-example edge tests passed"

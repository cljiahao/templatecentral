#!/usr/bin/env bash
# Behavioural test for skills/migrate/general/harness-live.sh.
# Seeds a fixture project from the real template trees, with fake lefthook and gitleaks binaries.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/skills/migrate/general/harness-live.sh"
SH="$ROOT/skills/scaffold/shared"
T=$(mktemp -d "${TMPDIR:-/tmp}/livetest.XXXXXX") || exit 1
trap '[ -d "$T" ] && rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in output"; fail=1 ;; esac; }

mkdir -p "$T/bin"
for b in lefthook gitleaks; do printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/$b"; chmod +x "$T/bin/$b"; done
mkdir -p "$T/nodebin" && ln -s "$(command -v node)" "$T/nodebin/node"
NODEDIR="$T/nodebin"
LIVEPATH="$T/bin:$NODEDIR:/usr/bin:/bin"

# seed <dir>: a fully seeded, wired project
seed() {
  local d=$1
  mkdir -p "$d/.claude/hooks" "$d/.lefthook" "$d/.github/workflows"
  cp -p "$SH"/template/.claude/hooks/* "$SH"/template-ts/.claude/hooks/* "$d/.claude/hooks/"
  cp -p "$SH"/template/.claude/ci-gates.sh "$SH"/template/.claude/verify-harness.sh "$d/.claude/"
  cp "$SH/template-settings-ts/.claude/settings.json" "$d/.claude/settings.json"
  cp "$SH/template-ts/lefthook.yml" "$d/lefthook.yml"
  cp "$SH/template/.gitleaks.toml" "$d/.gitleaks.toml"
  cp "$SH/template-ci/github-ts/.github/workflows/ci.yml" "$d/.github/workflows/ci.yml"
  # manifest of the enforcement layer, hashed from the seeded files
  (cd "$d" && python3 - <<'MAN'
import hashlib, json, os
paths = [os.path.join(r, f) for r, _, fs in os.walk(".claude/hooks") for f in fs]
paths += [".claude/ci-gates.sh", ".claude/verify-harness.sh", ".claude/settings.json", "lefthook.yml", ".gitleaks.toml", ".github/workflows/ci.yml"]
seeded = {p: {"path": p, "origin_hash": hashlib.sha256(open(p, "rb").read()).hexdigest()} for p in sorted(paths)}
json.dump({"seeded_files": seeded}, open(".claude/harness.json", "w"))
MAN
  )
  (cd "$d" && git init -q && printf '#!/bin/sh\nlefthook run pre-commit\n' >.git/hooks/pre-commit \
    && printf '#!/bin/sh\nlefthook run commit-msg\n' >.git/hooks/commit-msg && printf '#!/bin/sh\nlefthook run pre-push\n' >.git/hooks/pre-push \
    && chmod +x .git/hooks/pre-commit .git/hooks/commit-msg .git/hooks/pre-push)
}
run() { PATH="$LIVEPATH" bash "$SCRIPT" "$1" 2>&1; }

bash "$SCRIPT" >/dev/null 2>&1; check "no arguments exits 2" 2 $?
bash "$SCRIPT" "$T/nope" >/dev/null 2>&1; check "missing directory exits 2" 2 $?

# an unseeded project fails on every group
mkdir -p "$T/bare" && (cd "$T/bare" && git init -q)
out=$(run "$T/bare"); check "unseeded project exits 1" 1 $?
contains "unseeded: settings missing" "FAIL .claude/settings.json" "$out"
contains "unseeded: lefthook.yml missing" "FAIL lefthook.yml" "$out"
contains "unseeded: no CI" "FAIL CI workflow" "$out"

seed "$T/ok"
out=$(run "$T/ok"); check "seeded project exits 0" 0 $?

contains "seeded: all hooks registered" "PASS hook stop-checks executable and registered" "$out"
contains "seeded: user-prompt-guard needs no exec bit" "PASS hook user-prompt-guard executable and registered" "$out"
contains "seeded: summary" "OK: harness is live." "$out"
check "seeded project has no FAIL line" 0 "$(printf '%s\n' "$out" | grep -c '^FAIL')"

# each miss is reported and exits 1
seed "$T/m1"; rm -f "$T/m1/.git/hooks/pre-commit"
out=$(run "$T/m1"); check "unwired git hook exits 1" 1 $?
contains "unwired git hook named" "FAIL git hook pre-commit" "$out"

seed "$T/m2"; printf '#!/bin/sh\nexit 0\n' >"$T/m2/.git/hooks/commit-msg"
out=$(run "$T/m2"); check "git hook that skips lefthook exits 1" 1 $?
contains "git hook without lefthook named" "FAIL git hook commit-msg" "$out"

seed "$T/m3"; chmod -x "$T/m3/.claude/hooks/stop-checks.sh"
out=$(run "$T/m3"); check "non-executable hook exits 1" 1 $?
contains "non-executable hook named" "FAIL hook stop-checks" "$out"

seed "$T/m4"; rm "$T/m4/.claude/hooks/subagent-stop.sh"
out=$(run "$T/m4"); check "missing hook exits 1" 1 $?
contains "missing hook named" "FAIL hook subagent-stop: script missing" "$out"

seed "$T/m5"; sed -i.bak 's#session-context.sh#session-context.sh.gone#' "$T/m5/.claude/settings.json"; rm "$T/m5/.claude/settings.json.bak"
out=$(run "$T/m5"); check "unregistered hook exits 1" 1 $?
contains "unregistered hook named" "FAIL hook session-context: not registered" "$out"

seed "$T/m6"; python3 - "$T/m6/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
h = d["hooks"]["Stop"][0]["hooks"][0]; h["command"] = ["bash", h["args"][0]]
json.dump(d, open(p, "w"))
PY
out=$(run "$T/m6"); check "array-form command exits 1" 1 $?
contains "array-form command named" "FAIL settings.json hooks" "$out"

seed "$T/m7"
out=$(PATH="$NODEDIR:/usr/bin:/bin" bash "$SCRIPT" "$T/m7" 2>&1); check "missing lefthook and gitleaks exits 1" 1 $?
contains "missing lefthook named" "FAIL lefthook binary" "$out"
contains "missing gitleaks named" "FAIL gitleaks binary" "$out"

seed "$T/m8"; : >"$T/m8/.github/workflows/ci.yml"
out=$(run "$T/m8"); check "CI without gates exits 1" 1 $?
contains "CI without ci-gates named" "FAIL CI gates" "$out"
contains "CI without verify-harness named" "FAIL CI harness check" "$out"

seed "$T/m9"; rm -rf "$T/m9/.git"
out=$(run "$T/m9"); check "not a git repository exits 1" 1 $?
contains "not a git repository named" "FAIL git hooks: not a git repository" "$out"

# read-only: no write into the project, and the script never names an env or secret file
seed "$T/ro"; (cd "$T/ro" && git add -A && git -c user.email=t@t -c user.name=t commit -q --no-verify -m init)
before=$(cd "$T/ro" && find . -path ./.git -prune -o -type f -newer "$T/ro/lefthook.yml" -print | sort | tr '\n' ' ')
run "$T/ro" >/dev/null
after=$(cd "$T/ro" && find . -path ./.git -prune -o -type f -newer "$T/ro/lefthook.yml" -print | sort | tr '\n' ' ')
check "the run writes nothing into the project" "$before" "$after"
check "git status stays clean" 0 "$(cd "$T/ro" && git status --porcelain | wc -l | tr -d ' ')"
check "the script names no env or secret file outside the marked payload" 0 "$(grep -v 'PAYLOAD: synthetic' "$SCRIPT" | grep -cE '\.env|\.pem|secrets')"

# bypasses that proved presence, not firing
seed "$T/b1"; sed -i.bak 's#"Stop"#"Notification"#' "$T/b1/.claude/settings.json"; rm "$T/b1/.claude/settings.json.bak"
out=$(run "$T/b1"); check "hook under the wrong event exits 1" 1 $?
contains "wrong event named" "FAIL hook stop-checks: not registered under Stop" "$out"

seed "$T/b2"; printf '#!/usr/bin/env bash\nexit 0\n' >"$T/b2/.claude/hooks/stop-checks.sh"
out=$(run "$T/b2"); check "no-op hook exits 1" 1 $?
contains "no-op hook caught by the hash check" "FAIL verify-harness.sh" "$out"

seed "$T/b2g"; printf '#!/usr/bin/env bash\nexit 0\n' >"$T/b2g/.claude/hooks/protect-files.sh"
out=$(run "$T/b2g"); check "no-op guard exits 1" 1 $?
contains "no-op guard fails the firing check" "FAIL protect-files guard" "$out"
seed "$T/b2h"; printf '#!/usr/bin/env bash\nexit 0\n' >"$T/b2h/.claude/hooks/block-no-verify.sh"
out=$(run "$T/b2h"); contains "no-op no-verify guard fails the firing check" "FAIL block-no-verify guard" "$out"

seed "$T/b3"; sed -i.bak '1s#{#{"disableAllHooks": true,#' "$T/b3/.claude/settings.json"; rm "$T/b3/.claude/settings.json.bak"
out=$(run "$T/b3"); check "disableAllHooks exits 1" 1 $?
contains "disableAllHooks named" "FAIL settings.json disableAllHooks" "$out"

seed "$T/b4"; printf '# lefthook\n' >"$T/b4/.git/hooks/pre-commit"
out=$(run "$T/b4"); check "comment-only git hook exits 1" 1 $?
contains "comment-only git hook named" "FAIL git hook pre-commit" "$out"

seed "$T/b5"; printf '# ci-gates.sh\n# verify-harness.sh\nname: x\n' >"$T/b5/.github/workflows/ci.yml"
out=$(run "$T/b5"); check "CI mentions only in comments exits 1" 1 $?
contains "comment-only CI gates named" "FAIL CI gates" "$out"
contains "comment-only CI harness check named" "FAIL CI harness check" "$out"

seed "$T/b6"; rm "$T/b6/.claude/verify-harness.sh"
out=$(run "$T/b6"); check "missing verify-harness.sh exits 1" 1 $?
contains "missing verify-harness.sh named" "FAIL .claude/verify-harness.sh: missing" "$out"

seed "$T/b7"; printf '#!/usr/bin/env bash\n# edited\n' >>"$T/b7/.claude/hooks/subagent-stop.sh"
out=$(run "$T/b7"); check "edited guard layer exits 1" 1 $?
contains "edited guard layer named" "FAIL verify-harness.sh" "$out"

seed "$T/b8"; sed -i.bak '/^pre-push:/,$d' "$T/b8/lefthook.yml"; rm "$T/b8/lefthook.yml.bak"
out=$(run "$T/b8"); check "lefthook.yml without pre-push exits 1" 1 $?
contains "missing pre-push section named" "FAIL lefthook.yml pre-push" "$out"

seed "$T/b9"; sed -i.bak 's#gitleaks#gitl#g' "$T/b9/lefthook.yml"; rm "$T/b9/lefthook.yml.bak"
out=$(run "$T/b9"); check "lefthook.yml without gitleaks exits 1" 1 $?
contains "missing gitleaks command named" "FAIL lefthook.yml gitleaks" "$out"

seed "$T/b10"; rm "$T/b10/lefthook.yml"
out=$(run "$T/b10"); contains "missing lefthook.yml named" "FAIL lefthook.yml: missing" "$out"

# round 2: hook executability, hooksPath, local settings, lefthook commands, always-block guards
seed "$T/c1"; chmod -x "$T/c1/.git/hooks/pre-push"
out=$(run "$T/c1"); check "non-executable git hook exits 1" 1 $?
contains "non-executable git hook named" "FAIL git hook pre-push" "$out"

seed "$T/c2"; printf '#!/bin/sh\necho lefthook\nexit 0\n' >"$T/c2/.git/hooks/pre-commit"
out=$(run "$T/c2"); check "git hook that only echoes lefthook exits 1" 1 $?
seed "$T/c2b"; printf '#!/bin/sh\necho "lefthook run pre-commit"\nexit 0\n' >"$T/c2b/.git/hooks/pre-commit"
out=$(run "$T/c2b"); check "git hook that only echoes a lefthook run line exits 1" 1 $?
contains "echo-only git hook named" "FAIL git hook pre-commit" "$out"

seed "$T/c3"; mkdir "$T/c3/.githooks"; mv "$T/c3/.git/hooks/"* "$T/c3/.githooks/"; git -C "$T/c3" config core.hooksPath .githooks
out=$(run "$T/c3"); check "hooks under core.hooksPath pass" 0 $?
seed "$T/c3b"; git -C "$T/c3b" config core.hooksPath .nohooks
out=$(run "$T/c3b"); check "core.hooksPath without the hooks exits 1" 1 $?
contains "empty hooksPath named" "FAIL git hook pre-commit" "$out"

seed "$T/c4"; printf '{"disableAllHooks": true}\n' >"$T/c4/.claude/settings.local.json"
out=$(run "$T/c4"); check "disableAllHooks in settings.local.json exits 1" 1 $?
contains "local disableAllHooks named" "FAIL settings.local.json disableAllHooks" "$out"
case "$out" in *'"disableAllHooks"'*) echo "FAIL local settings content is printed"; fail=1 ;; *) echo "ok   local settings content is not printed" ;; esac
seed "$T/c4b"; printf '{"permissions": {"allow": []}}\n' >"$T/c4b/.claude/settings.local.json"
out=$(run "$T/c4b"); check "harmless settings.local.json passes" 0 $?

seed "$T/c5"; python3 - "$T/c5/lefthook.yml" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(?m)^pre-push:\n(?:[ \t].*\n|\n)*", "pre-push:\n  parallel: true\n", s)
open(p, "w").write(s)
PY2
out=$(run "$T/c5"); check "pre-push without commands exits 1" 1 $?
contains "empty pre-push commands named" "FAIL lefthook.yml pre-push" "$out"

seed "$T/c5b"; python3 - "$T/c5b/lefthook.yml" <<'PY3'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(?m)^pre-push:\n(?:[ \t].*\n|\n)*", "pre-push:\n  commands:\n", s)
open(p, "w").write(s)
PY3
out=$(run "$T/c5b"); check "pre-push with an empty commands block exits 1" 1 $?
contains "empty commands block named" "FAIL lefthook.yml pre-push" "$out"
seed "$T/c5c"; python3 - "$T/c5c/lefthook.yml" <<'PY4'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(?m)^pre-push:\n(?:[ \t].*\n|\n)*", "pre-push:\n    secret-scan:\n      run: gitleaks git\n", s)
open(p, "w").write(s)
PY4
out=$(run "$T/c5c"); check "pre-push with commands but no commands key exits 1" 1 $?
contains "missing commands key named" "FAIL lefthook.yml pre-push" "$out"

seed "$T/c6"; sed -i.bak 's#gitleaks git#echo git#; s#command -v gitleaks#command -v echo#' "$T/c6/lefthook.yml"; printf '    # gitleaks\n' >>"$T/c6/lefthook.yml"; rm "$T/c6/lefthook.yml.bak"
out=$(run "$T/c6"); check "gitleaks only in a comment exits 1" 1 $?
contains "comment-only gitleaks named" "FAIL lefthook.yml gitleaks" "$out"

seed "$T/c7"; printf '#!/usr/bin/env bash\necho "BLOCKED: always" >&2\nexit 2\n' >"$T/c7/.claude/hooks/protect-files.sh"
out=$(run "$T/c7"); check "an always-blocking guard exits 1" 1 $?
contains "always-blocking protect-files named" "FAIL protect-files guard: an ordinary write was blocked" "$out"
seed "$T/c8"; printf '#!/usr/bin/env bash\necho "BLOCKED: always" >&2\nexit 2\n' >"$T/c8/.claude/hooks/block-no-verify.sh"
out=$(run "$T/c8"); contains "always-blocking block-no-verify named" "FAIL block-no-verify guard: git status was blocked" "$out"

out=$(run "$T/ok"); contains "the output says the other hooks rest on the hash check" "covered by the .claude/verify-harness.sh hash check" "$out"

# a hook with a top-level exit before the lefthook call does not run it
seed "$T/h1"; printf '#!/bin/sh\nexit 0\nlefthook run pre-commit\n' >"$T/h1/.git/hooks/pre-commit"
out=$(run "$T/h1"); check "an early exit before lefthook exits 1" 1 $?
contains "early exit named" "FAIL git hook pre-commit" "$out"
seed "$T/h2"; printf '#!/bin/sh\nexit 0 # lefthook run pre-commit\n' >"$T/h2/.git/hooks/pre-commit"
out=$(run "$T/h2"); check "lefthook only in a trailing comment exits 1" 1 $?
contains "trailing comment named" "FAIL git hook pre-commit" "$out"
seed "$T/h3"; printf '#!/bin/sh\nif [ -z "%s" ]; then exit 0; fi\nlefthook run pre-commit\n' "\$CI" >"$T/h3/.git/hooks/pre-commit"
out=$(run "$T/h3"); check "a conditional exit before lefthook still passes" 0 $?

seed "$T/h5"; printf '#!/bin/sh\nlefthook version\n' >"$T/h5/.git/hooks/pre-commit"
out=$(run "$T/h5"); check "a hook that calls lefthook without run exits 1" 1 $?
contains "lefthook without run named" "FAIL git hook pre-commit" "$out"

# a hook shaped like the file lefthook install writes passes; the lefthook binary is not installed here, so this is a fixture of its known output
seed "$T/h4"
for h in pre-commit commit-msg pre-push; do
cat >"$T/h4/.git/hooks/$h" <<HOOK
#!/bin/sh

if [ "\$LEFTHOOK_VERBOSE" = "1" -o "\$LEFTHOOK_VERBOSE" = "true" ]; then
  set -x
fi

if [ "\$LEFTHOOK" = "0" ]; then
  exit 0
fi

call_lefthook()
{
  if test -n "\$LEFTHOOK_BIN"
  then
    "\$LEFTHOOK_BIN" "\$@"
  elif lefthook -h >/dev/null 2>&1
  then
    lefthook "\$@"
  else
    dir="\$(git rev-parse --show-toplevel)"
    osArch=\$(uname | tr '[:upper:]' '[:lower:]')
    if test -f "\$dir/node_modules/lefthook/bin/index.js"
    then
      "\$dir/node_modules/lefthook/bin/index.js" "\$@"
    else
      echo "Can't find lefthook in PATH"
    fi
  fi
}

call_lefthook run "$h" "\$@"
HOOK
chmod +x "$T/h4/.git/hooks/$h"
done
out=$(run "$T/h4"); check "a hook shaped like lefthook install output passes" 0 $?

# gitleaks must be the invoked command on a run line and not skipped
seed "$T/g1"; sed -i.bak 's#gitleaks git --pre-commit#echo gitleaks git --pre-commit#; s#command -v gitleaks#command -v echo#' "$T/g1/lefthook.yml"; rm "$T/g1/lefthook.yml.bak"
out=$(run "$T/g1"); check "run: echo gitleaks-not exits 1" 1 $?
contains "echo gitleaks named" "FAIL lefthook.yml gitleaks" "$out"
seed "$T/g2"; python3 - "$T/g2/lefthook.yml" <<'PY5'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(?m)^(    secret-scan:\n)", r"\1      skip: true\n", s, count=1)
open(p, "w").write(s)
PY5
grep -q 'skip: true' "$T/g2/lefthook.yml" || { echo "FAIL g2 fixture has no skip line"; fail=1; }
out=$(run "$T/g2"); check "a skipped gitleaks command exits 1" 1 $?
contains "skipped gitleaks named" "FAIL lefthook.yml gitleaks" "$out"

seed "$T/g3"; python3 - "$T/g3/lefthook.yml" <<'PY6'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(?m)^pre-commit:\n", "pre-commit:\n  skip: true\n", s, count=1)
open(p, "w").write(s)
PY6
grep -q '^  skip: true' "$T/g3/lefthook.yml" || { echo "FAIL g3 fixture has no hook skip line"; fail=1; }
out=$(run "$T/g3"); check "a skipped pre-commit hook exits 1" 1 $?
contains "skipped hook named" "FAIL lefthook.yml gitleaks" "$out"

# gitleaks through a package runner or docker passes; a non-scanning use fails
gl_variant() { # gl_variant <dir> <replacement run line> <jobs: 1 or 0>
  seed "$1"; python3 - "$1/lefthook.yml" "$2" "$3" <<'PY7'
import re, sys
p, run, jobs = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
s = open(p).read()
s = re.sub(r"(?m)^(      run: )if command -v gitleaks.*$", lambda m: m.group(1) + run, s, count=1)
if jobs:
    s = re.sub(r"(?m)^  commands:\n", "  jobs:\n", s)
    s = re.sub(r"(?m)^    ([A-Za-z0-9_-]+):\n", r"    - name: \1\n", s)
open(p, "w").write(s)
PY7
  # the edited lefthook.yml is the new seeded origin
  (cd "$1" && python3 - <<'RH'
import hashlib, json
m = json.load(open(".claude/harness.json"))
m["seeded_files"]["lefthook.yml"]["origin_hash"] = hashlib.sha256(open("lefthook.yml", "rb").read()).hexdigest()
json.dump(m, open(".claude/harness.json", "w"))
RH
  )
}
gl_ok() { gl_variant "$T/$1" "$2" "${3:-0}"; out=$(run "$T/$1"); check "gitleaks form passes: $2 jobs=${3:-0}" 0 $?; }
gl_no() { gl_variant "$T/$1" "$2" "${3:-0}"; out=$(run "$T/$1"); check "gitleaks form fails: $2 jobs=${3:-0}" 1 $?; contains "non-scanning gitleaks named: $2" "FAIL lefthook.yml gitleaks" "$out"; }
gl_ok r1 'npx gitleaks git --pre-commit --staged'
gl_ok r2 'pnpm exec gitleaks git --pre-commit --staged'
gl_ok r3 'pnpm dlx gitleaks git --pre-commit --staged'
# shellcheck disable=SC2016  # the run line is literal text for the fixture
gl_ok r4 'docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest git --pre-commit --staged /repo'
gl_ok r5 'gitleaks git --pre-commit --staged' 1
gl_ok r6 'npx gitleaks git --pre-commit --staged' 1
gl_no n1 'gitleaks version'
gl_no n2 'gitleaks --help'
gl_no n3 'echo gitleaks git'
gl_no n4 'gitleaks version' 1
gl_no n5 'echo gitleaks git' 1
gl_no n6 'gitleaks git --pre-commit --staged || true'
gl_no n7 'gitleaks git --pre-commit --staged || :'
gl_no n8 'gitleaks git --pre-commit --staged; true'
gl_no n9 'gitleaks git --pre-commit --staged || true' 1
gl_mixed() { gl_variant "$T/$1" "$2" 0; out=$(run "$T/$1"); check "gitleaks line not alone fails: $2" 1 $?; contains "only-command message: $2" "the gitleaks command must be the only command in the run line" "$out"; }
gl_mixed m1 'gitleaks git --staged || true # reason'
gl_mixed m2 'gitleaks git --staged || exit 0'
gl_mixed m3 'gitleaks git --staged; exit 0'
gl_mixed m4 'gitleaks git --staged; :'
gl_mixed m5 'gitleaks git --staged || echo skipped'
gl_mixed m6 'gitleaks git --staged || false'
gl_mixed m7 'gitleaks git --staged || return 0'
gl_mixed m8 'gitleaks git --staged || (true)'
gl_mixed m9 'gitleaks git --staged || /bin/true'
gl_mixed m10 'gitleaks git --staged | true'
gl_mixed m11 'gitleaks git --staged ||  true ;'
gl_mixed m12 'gitleaks git --staged &'
gl_mixed m13 'set +e; gitleaks git --staged'
gl_mixed m14 'false && gitleaks git --staged'
gl_mixed m15 'exit 0; gitleaks git --staged'
gl_mixed m16 'gitleaks git --staged || exit 1'
gl_mixed m17 $'|\n        set +e\n        gitleaks git --staged'
gl_mixed m18 $'|\n        gitleaks git --staged\n        true'
gl_ok a1 'gitleaks git --pre-commit --staged # scan staged files'
gl_ok a2 'gitleaks git --staged --config "my;rules.toml"'
gl_ok a3 "gitleaks git --staged --config 'a&b(c).toml'"
gl_ok a4 $'|\n        # scan staged\n\n        gitleaks git --pre-commit --staged'
gl_ok a6 '"gitleaks git --pre-commit --staged"'
gl_ok a7 'gitleaks git --pre-commit --staged' 1
seed "$T/n6"; python3 - "$T/n6/lefthook.yml" <<'PY8'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(?m)^  commands:\n", "  jobs:\n", s)
s = re.sub(r"(?m)^    ([A-Za-z0-9_-]+):\n", r"    - name: \1\n", s)
s = re.sub(r"(?m)^(    - name: secret-scan\n)", r"\1      skip: true\n", s, count=1)
open(p, "w").write(s)
PY8
seed "$T/n7"; python3 - "$T/n7/lefthook.yml" <<'PY9'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(?m)^  commands:\n", "  jobs:\n", s)
s = re.sub(r"(?m)^    ([A-Za-z0-9_-]+):\n", r"    - name: \1\n", s)
s = re.sub(r"(?m)^(    - name: typecheck\n)", r"\1      skip: true\n", s, count=1)
open(p, "w").write(s)
PY9
(cd "$T/n7" && python3 - <<'RH'
import hashlib, json
m = json.load(open(".claude/harness.json"))
m["seeded_files"]["lefthook.yml"]["origin_hash"] = hashlib.sha256(open("lefthook.yml", "rb").read()).hexdigest()
json.dump(m, open(".claude/harness.json", "w"))
RH
)
out=$(run "$T/n7"); check "a skip on another job does not fail gitleaks" 0 $?
out=$(run "$T/n6"); check "a skipped gitleaks job exits 1" 1 $?
contains "skipped gitleaks job named" "FAIL lefthook.yml gitleaks" "$out"

# invalid settings.local.json fails as unreadable and its contents are never printed
seed "$T/s1"; printf '{ "marker-9f3a": not json' >"$T/s1/.claude/settings.local.json"
out=$(run "$T/s1"); check "invalid settings.local.json exits 1" 1 $?
contains "invalid settings.local.json named" "FAIL settings.local.json" "$out"
case "$out" in *marker-9f3a*) echo "FAIL settings.local.json contents printed"; fail=1 ;; *) echo "ok   settings.local.json contents not printed" ;; esac
seed "$T/s2"; printf '{ "hooks": {}, "note": "marker-77c1" }' >"$T/s2/.claude/settings.local.json"
out=$(run "$T/s2"); check "valid settings.local.json passes" 0 $?
case "$out" in *marker-77c1*) echo "FAIL valid settings.local.json contents printed"; fail=1 ;; *) echo "ok   valid settings.local.json contents not printed" ;; esac


# round 7: plain-scalar continuation folds into the run value
for j in 0 1; do
gl_mixed_j() { gl_variant "$T/$1" "$2" "$3"; out=$(run "$T/$1"); check "gitleaks line not alone fails: $2 jobs=$3" 1 $?; contains "only-command message: $2 jobs=$3" "the gitleaks command must be the only command in the run line" "$out"; }
gl_mixed_j c1$j $'gitleaks git --staged\n          || true' $j
gl_mixed_j c2$j $'gitleaks git --staged\n          ; exit 0' $j
gl_mixed_j c3$j $'gitleaks git --staged\n          | true' $j
gl_mixed_j c4$j $'gitleaks git --staged \\\n          || true' $j
gl_mixed_j c5$j $'gitleaks git --staged\n\n          || true' $j
gl_mixed_j c6$j $'gitleaks git --staged \\' $j
done
gl_ok c7 $'gitleaks git --pre-commit\n          --staged'
gl_ok c8 $'gitleaks git --pre-commit\n          --staged # note'
# round 7: duplicate run key, gating keys
gl_msg() { gl_variant "$T/$1" "$2" 0; out=$(run "$T/$1"); check "fails: $2" 1 $?; contains "message for: $2" "$3" "$out"; }
gl_msg d1 $'gitleaks git --staged\n      run: true' "more than one run:"
for k in "skip: true" "skip: CI" "only: false" "exclude: '*'" "glob: '*.nothing'" "files: echo" "env: {A: b}"; do
  gl_msg "k-${k%%:*}-${k##* }" "$(printf 'gitleaks git --staged\n      %s' "$k")" "sets ${k%%:*}:"
done
gl_ok kf $'gitleaks git --staged\n      skip: false'
gl_ok kt $'gitleaks git --staged\n      tags: security\n      stage_fixed: true\n      fail_text: stop\n      priority: 1\n      root: ./'
# round 7: neutering arguments
i=0
for a in '--exit-code 0' '--exit-code=0' '--no-git' '--baseline-path x.json' '--max-target-megabytes 1' '--log-opts=-1' '--enable-rule x' '-c /dev/null' '--config /dev/null' '--config=/dev/null' '--config ""' '-c' '--bogus'; do
  i=$((i+1)); gl_msg "x$i" "gitleaks git --staged $a" "is not accepted"
done
gl_msg e1 'GITLEAKS_CONFIG=/dev/null gitleaks git --staged' "is not accepted"
gl_msg e2 'FOO=1 npx gitleaks git --staged' "is not accepted"
# shellcheck disable=SC2016
gl_msg e3 'docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest git --staged /repo' '"$PWD"'
gl_ok f1 'gitleaks protect --staged -v --verbose --no-color --log-level debug --redact=50 --config ok.toml'
gl_ok f2 'gitleaks detect --redact 20 --no-banner'
exit $fail

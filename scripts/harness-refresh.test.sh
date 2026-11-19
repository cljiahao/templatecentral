#!/usr/bin/env bash
# Behavioural test for skills/migrate/general/harness-refresh.sh.
# Seeds a fixture project with tc-copy.sh, ages or edits files, and checks each class, the dry run, --apply and the refusals.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/skills/migrate/general/harness-refresh.sh"
COPY="$ROOT/skills/scaffold/shared/tc-copy.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/refreshtest.XXXXXX") || exit 1
trap '[ -d "$T" ] && rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in output"; fail=1 ;; esac; }
absent() { case "$3" in *"$2"*) echo "FAIL $1: [$2] found in output"; fail=1 ;; *) echo "ok   $1" ;; esac; }

mkdir -p "$T/bin"
for b in lefthook gitleaks; do printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/$b"; chmod +x "$T/bin/$b"; done
mkdir -p "$T/nodebin" && ln -s "$(command -v node)" "$T/nodebin/node"
RUNPATH="$T/bin:$T/nodebin:/usr/bin:/bin"

sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1"; else sha256sum -- "$1"; fi | cut -d' ' -f1; }
# treehash <dir>: one hash over every file path, mode-independent content and symlink target, .git excluded
treehash() { (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then printf '%s L %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(sha "$f")"; fi; done | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1); }
run() { local d=$1; shift; PATH="$RUNPATH" bash "$SCRIPT" "$d" "$@" 2>&1; }

# seed <dir> <stack>: a seeded project with records, base snapshot, wired git hooks, committed
seed() {
  local d=$1 s=$2 part skill
  mkdir -p "$d"
  for part in base stack agents settings late; do
    TC_STACK=$s TC_PART=$part bash "$COPY" "$d" >/dev/null 2>&1 || { echo "FAIL seed $s part $part"; fail=1; return 1; }
  done
  TC_STACK=$s TC_PART=ci TC_CI=github bash "$COPY" "$d" >/dev/null 2>&1 || { echo "FAIL seed $s ci"; fail=1; return 1; }
  printf '@AGENTS.md\n' >"$d/CLAUDE.md"
  case "$s" in fastapi) skill=api-verify ;; nestjs) skill=nest-verify ;; nextjs) skill=next-verify ;; *) skill=vite-verify ;; esac
  mkdir -p "$d/.claude/skills/$skill"
  printf -- '---\nname: %s\n---\n' "$skill" >"$d/.claude/skills/$skill/SKILL.md"
  [ "$s" = nextjs ] && { mkdir -p "$d/.claude/skills/next-migrate"; printf -- '---\nname: next-migrate\n---\n' >"$d/.claude/skills/next-migrate/SKILL.md"; }
  case "$s" in
    nestjs) echo '{"dependencies":{"@nestjs/core":"1"}}' >"$d/package.json" ;;
    nextjs) echo '{}' >"$d/package.json"; echo 'export default {}' >"$d/next.config.ts" ;;
    vite-react) echo '{}' >"$d/package.json"; echo 'export default {}' >"$d/vite.config.ts" ;;
    fastapi) echo 'fastapi' >"$d/requirements.txt" ;;
  esac
  TC_STACK=$s TC_PART=manifest bash "$COPY" "$d" >/dev/null 2>&1 || { echo "FAIL seed $s manifest"; fail=1; return 1; }
  (cd "$d" && python3 -c "import json;[print(v['path']) for v in json.load(open('.claude/harness.json'))['seeded_files'].values()]" | while IFS= read -r p; do
    mkdir -p ".claude/.harness-base/$(dirname "$p")"; cp "$p" ".claude/.harness-base/$p"; done
    git init -q -b main \
    && printf '#!/bin/sh\nlefthook run pre-commit\n' >.git/hooks/pre-commit && printf '#!/bin/sh\nlefthook run commit-msg\n' >.git/hooks/commit-msg \
    && printf '#!/bin/sh\nlefthook run pre-push\n' >.git/hooks/pre-push && chmod +x .git/hooks/pre-commit .git/hooks/commit-msg .git/hooks/pre-push \
    && git add -A && git -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm seed)
}
# age <dir> <path>: make the file an older template version, recorded as seeded (file, record and base agree)
age() {
  local d=$1 p=$2
  printf '# older template line\n' >>"$d/$p"
  cp "$d/$p" "$d/.claude/.harness-base/$p"
  (cd "$d" && python3 - "$p" <<'PY'
import hashlib, json, sys
j = json.load(open(".claude/harness.json"))
j["seeded_files"][sys.argv[1]]["origin_hash"] = hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest()
json.dump(j, open(".claude/harness.json", "w"), indent=2)
PY
  )
}
commit() { (cd "$1" && git add -A && git -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm "$2"); }

bash "$SCRIPT" >/dev/null 2>&1; check "no arguments exits 2" 2 $?
bash "$SCRIPT" "$T/nope" >/dev/null 2>&1; check "missing directory exits 2" 2 $?
bash "$SCRIPT" "$T" --baseline "$T" >/dev/null 2>&1; check "--baseline without --apply exits 2" 2 $?
mkdir -p "$T/empty"
out=$(run "$T/empty"); check "no stack exits 2" 2 $?
contains "no stack named" "no stack detected" "$out"

# a seeded project that matches the templates
seed "$T/ok" nestjs
out=$(run "$T/ok"); check "fresh seed exits 0" 0 $?
contains "fresh seed: summary" "0 to replace, 0 to add, 0 modified" "$out"
absent "fresh seed: no REPLACE" "REPLACE" "$out"

# every class at once, on one project
seed "$T/p" nestjs
age "$T/p" .claude/hooks/stop-checks.sh
printf '# my rule\n' >>"$T/p/.claude/hooks/protect-files.sh"
age "$T/p" lefthook.yml
rm "$T/p/.claude/hooks/subagent-stop.sh"
printf '# old\n' >>"$T/p/.claude/comment-hygiene-patterns.txt"
python3 - "$T/p" <<'PY'
import json, sys
f = sys.argv[1] + "/.claude/harness.json"
j = json.load(open(f))
j["seeded_files"][".claude/hooks/post-tool-failure.sh"] = {"origin_hash": "0" * 64, "path": ".claude/hooks/post-tool-failure.sh"}
json.dump(j, open(f, "w"), indent=2)
PY
printf 'extra\n' >"$T/p/.claude/hooks/post-tool-failure.sh"
chmod -x "$T/p/.claude/hooks/block-no-verify.sh"
sed -i.bak 's/__TC_PROJECT_TITLE__/My Real Project/' "$T/p/docs/CONSTITUTION.md"; rm -f "$T/p/docs/CONSTITUTION.md.bak"
commit "$T/p" edits

before=$(treehash "$T/p")
out=$(run "$T/p"); rc=$?
check "dry run with a modified file exits 1" 1 $rc
check "dry run changes nothing (tree hash)" "$before" "$(treehash "$T/p")"
check "dry run adds no file" 0 "$(find "$T/p" -name '*.templatecentral-new' | wc -l | tr -d ' ')"
contains "SAME class" "SAME      .claude/hooks/session-context.sh" "$out"
contains "REPLACE class (aged, proven)" "REPLACE   .claude/hooks/stop-checks.sh  (unmodified since seeded)" "$out"
contains "REPLACE class (aged lefthook)" "REPLACE   lefthook.yml" "$out"
contains "REPLACE class (mode only)" "REPLACE   .claude/hooks/block-no-verify.sh  (content identical; mode set to 755)" "$out"
contains "MODIFIED class (edited)" "MODIFIED  .claude/hooks/protect-files.sh  (differs from its recorded origin hash)" "$out"
contains "MODIFIED class (no proof: record not updated)" "MODIFIED  .claude/comment-hygiene-patterns.txt" "$out"
contains "ADD class" "ADD       .claude/hooks/subagent-stop.sh" "$out"
contains "GONE class" "GONE      .claude/hooks/post-tool-failure.sh  (no longer seeded; still on disk, left alone)" "$out"
contains "placeholder file with a real title is SAME" "SAME      docs/CONSTITUTION.md  (placeholder file)" "$out"
contains "summary line" "summary: " "$out"
contains "needs-you line" "NEEDS YOU" "$out"

# --apply
mod_hash=$(sha "$T/p/.claude/hooks/protect-files.sh")
mod2_hash=$(sha "$T/p/.claude/comment-hygiene-patterns.txt")
gone_hash=$(sha "$T/p/.claude/hooks/post-tool-failure.sh")
out=$(run "$T/p" --apply); rc=$?
check "apply with modified files exits 1" 1 $rc
check "apply never touches a modified file" "$mod_hash" "$(sha "$T/p/.claude/hooks/protect-files.sh")"
check "apply never touches an unproven file" "$mod2_hash" "$(sha "$T/p/.claude/comment-hygiene-patterns.txt")"
check "apply never deletes a GONE file" "$gone_hash" "$(sha "$T/p/.claude/hooks/post-tool-failure.sh")"
check "modified file gets the new version beside it" "$(sha "$ROOT/skills/scaffold/shared/template-ts/.claude/hooks/protect-files.sh")" "$(sha "$T/p/.claude/hooks/protect-files.sh.templatecentral-new")"
check "replaced file equals the template" "$(sha "$ROOT/skills/scaffold/shared/template-ts/.claude/hooks/stop-checks.sh")" "$(sha "$T/p/.claude/hooks/stop-checks.sh")"
check "added file equals the template" "$(sha "$ROOT/skills/scaffold/shared/template-ts/.claude/hooks/subagent-stop.sh")" "$(sha "$T/p/.claude/hooks/subagent-stop.sh")"
check "added hook is executable" 1 "$([ -x "$T/p/.claude/hooks/subagent-stop.sh" ] && echo 1 || echo 0)"
check "mode-only fix applied" 1 "$([ -x "$T/p/.claude/hooks/block-no-verify.sh" ] && echo 1 || echo 0)"
contains "apply lists the file for the user" "NEEDS YOU: merge each new version" "$out"
contains "apply runs the live check" "live check:" "$out"
rec=$(python3 -c "import json;print(json.load(open('$T/p/.claude/harness.json'))['seeded_files']['.claude/hooks/stop-checks.sh']['origin_hash'])")
check "record refreshed for a replaced file" "$(sha "$T/p/.claude/hooks/stop-checks.sh")" "$rec"
check "base refreshed for a replaced file" "$(sha "$T/p/.claude/hooks/stop-checks.sh")" "$(sha "$T/p/.claude/.harness-base/.claude/hooks/stop-checks.sh")"
check "record added for an added file" 1 "$(grep -c '"path": ".claude/hooks/subagent-stop.sh"' "$T/p/.claude/harness.json")"
out=$(run "$T/p" --allow-dirty)
contains "second dry run: replaced file is SAME" "SAME      .claude/hooks/stop-checks.sh" "$out"
contains "second dry run: modified file still MODIFIED" "MODIFIED  .claude/hooks/protect-files.sh" "$out"

# nothing needs the user: a clean apply exits 0
seed "$T/c" nestjs
age "$T/c" .claude/hooks/stop-checks.sh
rm "$T/c/.claude/hooks/subagent-stop.sh"
commit "$T/c" aged
out=$(run "$T/c" --apply); rc=$?
check "clean apply exits 0" 0 $rc
contains "clean apply: live check passes" "OK: harness is live." "$out"
check "clean apply: only harness paths changed" 0 "$(git -C "$T/c" status --porcelain -uall | grep -vc ' \.claude/')"
out=$(run "$T/c"); check "dry run after a clean apply exits 0" 0 $?
contains "dry run after a clean apply: nothing to do" "0 to replace, 0 to add, 0 modified" "$out"

# dirty tree refusal
seed "$T/d" nestjs
age "$T/d" .claude/hooks/stop-checks.sh
commit "$T/d" aged
echo scratch >"$T/d/notes.txt"
before=$(treehash "$T/d")
out=$(run "$T/d" --apply); check "dirty tree: apply refused with 2" 2 $?
contains "dirty tree: reason" "git tree is dirty" "$out"
check "dirty tree: nothing written" "$before" "$(treehash "$T/d")"
out=$(run "$T/d"); check "dirty tree: dry run still allowed" 0 $?
contains "dirty tree: dry run notes it" "the tree is dirty" "$out"
out=$(run "$T/d" --apply --allow-dirty); check "dirty tree: --allow-dirty applies" 0 $?

# no git: apply refused
seed "$T/ng" nestjs
age "$T/ng" .claude/hooks/stop-checks.sh
rm -rf "$T/ng/.git"
out=$(run "$T/ng" --apply); check "no git: apply refused with 2" 2 $?

# proof missing: no base snapshot, no record
seed "$T/nb" nestjs
age "$T/nb" .claude/hooks/stop-checks.sh
rm -rf "$T/nb/.claude/.harness-base"
commit "$T/nb" nobase
out=$(run "$T/nb")
contains "no base copy: not replaced" "MODIFIED  .claude/hooks/stop-checks.sh  (no seeded copy under .claude/.harness-base" "$out"
seed "$T/nr" nestjs
printf '# older\n' >>"$T/nr/.claude/hooks/stop-checks.sh"
rm "$T/nr/.claude/harness.json"
commit "$T/nr" norecord
out=$(run "$T/nr")
contains "no record: not replaced" "MODIFIED  .claude/hooks/stop-checks.sh  (no origin hash recorded" "$out"
out=$(run "$T/nr" --apply); check "no records: apply still exits 1" 1 $?

# other stacks detect and plan
for s in nextjs vite-react fastapi; do
  seed "$T/s-$s" "$s"
  out=$(run "$T/s-$s"); check "$s: fresh seed exits 0" 0 $?
  contains "$s: stack detected" "stack $s," "$out"
done
mkdir -p "$T/amb" && echo '{}' >"$T/amb/next.config.ts" && echo 'fastapi' >"$T/amb/requirements.txt"
out=$(run "$T/amb"); check "ambiguous stack exits 2" 2 $?

# paths with spaces
seed "$T/with space/my proj" nestjs
age "$T/with space/my proj" .claude/hooks/stop-checks.sh
commit "$T/with space/my proj" aged
out=$(run "$T/with space/my proj" --apply); check "path with spaces: apply exits 0" 0 $?
check "path with spaces: replaced" "$(sha "$ROOT/skills/scaffold/shared/template-ts/.claude/hooks/stop-checks.sh")" "$(sha "$T/with space/my proj/.claude/hooks/stop-checks.sh")"

# symlinked target directory
ln -s "$T/c" "$T/link"
out=$(run "$T/link"); check "symlinked target: dry run exits 0" 0 $?
contains "symlinked target: resolved" "harness refresh: $(cd -P "$T/c" && pwd -P)" "$out"

# symlinks inside the project are never written through
seed "$T/sl" nestjs
outside="$T/outside.txt"; echo keep >"$outside"
rm "$T/sl/.claude/hooks/stop-checks.sh"; ln -s "$outside" "$T/sl/.claude/hooks/stop-checks.sh"
commit "$T/sl" symlink
out=$(run "$T/sl" --apply); check "symlinked file: exits 1" 1 $?
check "symlinked file: target untouched" "keep" "$(cat "$outside")"
contains "symlinked file: reported" "path is or sits under a symlink" "$out"
seed "$T/sc" nestjs
mv "$T/sc/.claude" "$T/sc-claude" && ln -s "$T/sc-claude" "$T/sc/.claude"
out=$(run "$T/sc"); check "symlinked .claude: refused with 2" 2 $?

# a file that already has a .templatecentral-new symlink is not written through
seed "$T/nl" nestjs
printf 'edit\n' >>"$T/nl/.claude/hooks/protect-files.sh"
echo keep >"$T/nl-out.txt"; ln -s "$T/nl-out.txt" "$T/nl/.claude/hooks/protect-files.sh.templatecentral-new"
commit "$T/nl" edit
run "$T/nl" --apply >/dev/null; check "new-version symlink: target untouched" "keep" "$(cat "$T/nl-out.txt")"

exit $fail

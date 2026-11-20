#!/usr/bin/env bash
# Behavioural test for skills/migrate/general/harness-refresh.sh.
# Seeds a fixture project with tc-copy.sh, ages or edits files, and checks each class, the dry run, --apply and the refusals.
# The script runs from a copy of the plugin in a temp dir, so its pristine-hashes.txt can list the "older released" files the cases make.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COPY="$ROOT/skills/scaffold/shared/tc-copy.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/refreshtest.XXXXXX") || exit 1
trap '[ -d "$T" ] && rm -rf "$T"' EXIT
PLUG="$T/plugin"
mkdir -p "$PLUG/skills/migrate" "$PLUG/skills/scaffold"
cp -R "$ROOT/skills/migrate/general" "$PLUG/skills/migrate/general"
cp -R "$ROOT/skills/scaffold/shared" "$PLUG/skills/scaffold/shared"
cp -R "$ROOT/.claude-plugin" "$PLUG/.claude-plugin"
SCRIPT="$PLUG/skills/migrate/general/harness-refresh.sh"
PRIST="$PLUG/skills/migrate/general/pristine-hashes.txt"
printf '%s\t7.0.0\tdocs/never-used.md\n' "$(printf 'x' | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1)" >"$PRIST"
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
  printf '%s\t7.0.0\t%s\n' "$(sha "$d/$p")" "$p" >>"$PRIST"
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

# the files recorded since the test budget landed are classified like any other seeded file
seed "$T/rec" nestjs
for f in scripts/test-budget.sh .claude/skills/test-consolidate/SKILL.md docs/adr/0001-test-each-behaviour-once.md docs/harness.md .github/dependabot.yml; do
  contains "record present: $f" "\"$f\"" "$(cat "$T/rec/.claude/harness.json")"
done
age "$T/rec" scripts/test-budget.sh
age "$T/rec" docs/harness.md
age "$T/rec" .github/dependabot.yml
age "$T/rec" .claude/skills/test-consolidate/SKILL.md
printf '# local note\n' >>"$T/rec/docs/adr/0001-test-each-behaviour-once.md"
commit "$T/rec" aged
out=$(run "$T/rec"); rc=$?
check "recorded files: a local edit exits 1" 1 $rc
contains "test-budget.sh aged is REPLACE" "REPLACE   scripts/test-budget.sh  (unmodified since seeded: identical to the file released in 7.0.0)" "$out"
contains "harness.md aged is REPLACE" "REPLACE   docs/harness.md  (unmodified since seeded: identical to the file released in 7.0.0)" "$out"
contains "dependabot.yml aged is REPLACE" "REPLACE   .github/dependabot.yml  (unmodified since seeded: identical to the file released in 7.0.0)" "$out"
contains "test-consolidate skill aged is REPLACE" "REPLACE   .claude/skills/test-consolidate/SKILL.md  (unmodified since seeded: identical to the file released in 7.0.0)" "$out"
contains "edited ADR is MODIFIED" "MODIFIED  docs/adr/0001-test-each-behaviour-once.md  (not identical to any released template; treated as edited)" "$out"

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
contains "REPLACE class (aged, proven)" "REPLACE   .claude/hooks/stop-checks.sh  (unmodified since seeded: identical to the file released in 7.0.0)" "$out"
contains "REPLACE class (aged lefthook)" "REPLACE   lefthook.yml" "$out"
contains "REPLACE class (mode only)" "REPLACE   .claude/hooks/block-no-verify.sh  (content identical; mode set to 755)" "$out"
contains "MODIFIED class (edited)" "MODIFIED  .claude/hooks/protect-files.sh  (not identical to any released template; treated as edited)" "$out"
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
if [ -x "$T/p/.claude/hooks/subagent-stop.sh" ]; then isx=1; else isx=0; fi
check "added hook is executable" 1 "$isx"
if [ -x "$T/p/.claude/hooks/block-no-verify.sh" ]; then isx=1; else isx=0; fi
check "mode-only fix applied" 1 "$isx"
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

# the project records are not the proof: a missing base snapshot or record changes nothing
seed "$T/nb" nestjs
age "$T/nb" .claude/hooks/stop-checks.sh
rm -rf "$T/nb/.claude/.harness-base"
commit "$T/nb" nobase
out=$(run "$T/nb")
contains "no base copy: the pristine proof does not need it" "REPLACE   .claude/hooks/stop-checks.sh  (unmodified since seeded: identical to the file released in 7.0.0)" "$out"
seed "$T/nr" nestjs
printf '# older\n' >>"$T/nr/.claude/hooks/stop-checks.sh"
rm "$T/nr/.claude/harness.json"
commit "$T/nr" norecord
out=$(run "$T/nr")
contains "no record, not on the released list: not replaced" "MODIFIED  .claude/hooks/stop-checks.sh  (not identical to any released template; treated as edited)" "$out"
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

# a symlinked .claude/.harness-base is refused before any write, nothing lands outside
seed "$T/hb" nestjs
age "$T/hb" .claude/hooks/stop-checks.sh
rm "$T/hb/.claude/hooks/subagent-stop.sh"
mv "$T/hb/.claude/.harness-base" "$T/hb-outside" && ln -s "$T/hb-outside" "$T/hb/.claude/.harness-base"
commit "$T/hb" basesymlink
before=$(treehash "$T/hb"); outside_before=$(treehash "$T/hb-outside")
out=$(run "$T/hb" --apply); check "symlinked .harness-base: refused with 2" 2 $?
contains "symlinked .harness-base: reason" "refusing: .claude/.harness-base is a symlink" "$out"
check "symlinked .harness-base: project tree untouched" "$before" "$(treehash "$T/hb")"
check "symlinked .harness-base: outside directory untouched" "$outside_before" "$(treehash "$T/hb-outside")"

# a symlinked harness.json is refused before any write
seed "$T/hj" nestjs
age "$T/hj" .claude/hooks/stop-checks.sh
mv "$T/hj/.claude/harness.json" "$T/hj-out.json" && ln -s "$T/hj-out.json" "$T/hj/.claude/harness.json"
commit "$T/hj" hjsymlink
before=$(treehash "$T/hj"); outside_before=$(sha "$T/hj-out.json")
out=$(run "$T/hj" --apply); check "symlinked harness.json: refused with 2" 2 $?
contains "symlinked harness.json: reason" "harness.json is a symlink" "$out"
check "symlinked harness.json: project tree untouched" "$before" "$(treehash "$T/hj")"
check "symlinked harness.json: outside file untouched" "$outside_before" "$(sha "$T/hj-out.json")"

# a .templatecentral-new that is a directory fails for that file, leaves no temp file, and ends with the partial summary
seed "$T/sd" nestjs
printf 'edit\n' >>"$T/sd/.claude/hooks/protect-files.sh"
age "$T/sd" .claude/hooks/stop-checks.sh
rm "$T/sd/.claude/hooks/subagent-stop.sh"
mkdir "$T/sd/.claude/hooks/protect-files.sh.templatecentral-new"
commit "$T/sd" sidecardir
out=$(run "$T/sd" --apply); check "sidecar is a directory: exits 1" 1 $?
contains "sidecar is a directory: reported" "FAILED   .claude/hooks/protect-files.sh.templatecentral-new (it exists and is not a regular file)" "$out"
absent "sidecar is a directory: not claimed written" "wrote    .claude/hooks/protect-files.sh.templatecentral-new" "$out"
check "sidecar is a directory: no temp file left" 0 "$(find "$T/sd" -name '.tc-refresh.*' | wc -l | tr -d ' ')"
check "sidecar is a directory: still empty" 0 "$(find "$T/sd/.claude/hooks/protect-files.sh.templatecentral-new" -mindepth 1 | wc -l | tr -d ' ')"
contains "partial summary after FAILED" "PARTIAL: the tree is partly applied. written:" "$out"
contains "partial summary lists what was written" ".claude/hooks/stop-checks.sh" "$(printf '%s\n' "$out" | grep '^PARTIAL')"
contains "partial summary lists what was not" "not written: .claude/hooks/protect-files.sh.templatecentral-new" "$out"
absent "partial run: no commit advice" "then commit the refresh" "$out"
check "partial run: PARTIAL is the last line" "PARTIAL" "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-7)"

# a .templatecentral-new that already exists is never overwritten; an identical one is a merge still pending
seed "$T/sf" nestjs
printf 'edit\n' >>"$T/sf/.claude/hooks/protect-files.sh"
printf 'my merge in progress\n' >"$T/sf/.claude/hooks/protect-files.sh.templatecentral-new"
commit "$T/sf" sidecarfile
out=$(run "$T/sf" --apply); check "differing sidecar: exits 1" 1 $?
check "differing sidecar: kept as it was" "my merge in progress" "$(cat "$T/sf/.claude/hooks/protect-files.sh.templatecentral-new")"
contains "differing sidecar: reported as kept, not overwritten" "kept     .claude/hooks/protect-files.sh.templatecentral-new (an older or edited sidecar differs from the new version and is not overwritten" "$out"
absent "differing sidecar: not a failure" "FAILED" "$out"
absent "differing sidecar: no PARTIAL line" "PARTIAL" "$out"
contains "differing sidecar: exit message says merges are pending" "Exit 1: 1 file(s) wait for a merge; the refresh itself did not fail." "$out"
seed "$T/sp" nestjs
printf 'edit\n' >>"$T/sp/.claude/hooks/protect-files.sh"
commit "$T/sp" edited
out=$(run "$T/sp" --apply); check "first apply: exits 1" 1 $?
contains "first apply: sidecar written" "wrote    .claude/hooks/protect-files.sh.templatecentral-new" "$out"
commit "$T/sp" sidecar
out=$(run "$T/sp" --apply); check "second apply with the same sidecar: still exits 1" 1 $?
contains "second apply: pending, not failed" "pending  .claude/hooks/protect-files.sh.templatecentral-new (already written, identical to the new version" "$out"
absent "second apply: no FAILED" "FAILED" "$out"
absent "second apply: no PARTIAL" "PARTIAL" "$out"
contains "second apply: exit message says merges are pending" "Exit 1: 1 file(s) wait for a merge" "$out"
rm "$T/sp/.claude/hooks/protect-files.sh.templatecentral-new"
cp "$ROOT/skills/scaffold/shared/template-ts/.claude/hooks/protect-files.sh" "$T/sp/.claude/hooks/protect-files.sh"
commit "$T/sp" merged
out=$(run "$T/sp" --apply); check "control, merged and sidecar removed: exits 0" 0 $?
absent "control: nothing pending" "pending " "$out"

# a REPLACE file that changes between the plan and the write is treated as MODIFIED
mkdir -p "$T/gitbin"
REALGIT=$(command -v git)
cat >"$T/gitbin/git" <<EOF
#!/usr/bin/env bash
out=\$("$REALGIT" "\$@"); rc=\$?
printf '%s\n' "\$out"
case " \$* " in *" status "*) if [ -n "\${TC_RACE:-}" ] && [ ! -e "\$TC_RACE.done" ]; then printf '# race\n' >>"\$TC_RACE"; : >"\$TC_RACE.done"; fi ;; esac
exit \$rc
EOF
chmod +x "$T/gitbin/git"
seed "$T/rc" nestjs
age "$T/rc" .claude/hooks/stop-checks.sh
commit "$T/rc" aged
out=$(PATH="$T/gitbin:$RUNPATH" TC_RACE="$T/rc/.claude/hooks/stop-checks.sh" bash "$SCRIPT" "$T/rc" --apply 2>&1); check "changed since the plan: exits 1" 1 $?
contains "changed since the plan: reported" "changed  .claude/hooks/stop-checks.sh since the plan; treated as MODIFIED" "$out"
check "changed since the plan: file not replaced" 1 "$(grep -c '^# race$' "$T/rc/.claude/hooks/stop-checks.sh")"
check "changed since the plan: new version beside it" "$(sha "$ROOT/skills/scaffold/shared/template-ts/.claude/hooks/stop-checks.sh")" "$(sha "$T/rc/.claude/hooks/stop-checks.sh.templatecentral-new")"

# rehash <dir> <path>: set the record to the file's current hash (a forged record)
rehash() {
  (cd "$1" && python3 - "$2" <<'PY'
import hashlib, json, sys
j = json.load(open(".claude/harness.json"))
j["seeded_files"][sys.argv[1]]["origin_hash"] = hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest()
json.dump(j, open(".claude/harness.json", "w"), indent=2)
PY
  )
}
# forged record: file edited and record changed to match, base copy left old
seed "$T/fr" nestjs
age "$T/fr" .claude/hooks/stop-checks.sh
printf '# sneaky local edit\n' >>"$T/fr/.claude/hooks/stop-checks.sh"
rehash "$T/fr" .claude/hooks/stop-checks.sh
commit "$T/fr" forged
out=$(run "$T/fr")
contains "forged record: MODIFIED" "MODIFIED  .claude/hooks/stop-checks.sh  (not identical to any released template; treated as edited)" "$out"
# base copy drift alone: the file is a released one, so the drift does not matter
seed "$T/bm" nestjs
age "$T/bm" .claude/hooks/stop-checks.sh
printf '# base drift\n' >>"$T/bm/.claude/.harness-base/.claude/hooks/stop-checks.sh"
commit "$T/bm" basedrift
out=$(run "$T/bm")
contains "base drift alone: still REPLACE" "REPLACE   .claude/hooks/stop-checks.sh  (unmodified since seeded: identical to the file released in 7.0.0)" "$out"
# whitespace-only and CRLF edits are edits
seed "$T/ws" nestjs
age "$T/ws" .claude/hooks/stop-checks.sh
age "$T/ws" lefthook.yml
sed -i.bak '1s/$/ /' "$T/ws/.claude/hooks/stop-checks.sh"; rm -f "$T/ws/.claude/hooks/stop-checks.sh.bak"
awk '{ printf "%s\r\n", $0 }' "$T/ws/lefthook.yml" >"$T/ws/lefthook.crlf" && mv "$T/ws/lefthook.crlf" "$T/ws/lefthook.yml"
commit "$T/ws" whitespace
out=$(run "$T/ws")
contains "whitespace-only edit: MODIFIED" "MODIFIED  .claude/hooks/stop-checks.sh  (not identical to any released template; treated as edited)" "$out"
contains "CRLF edit: MODIFIED" "MODIFIED  lefthook.yml  (not identical to any released template; treated as edited)" "$out"

# record entries that point outside the project are never written or removed
seed "$T/ev" nestjs
echo keep >"$T/evil"; echo keep >"$T/abs-file"
python3 - "$T/ev" "$T/abs-file" <<'PY'
import json, sys
f = sys.argv[1] + "/.claude/harness.json"
j = json.load(open(f))
for p in ("../evil", sys.argv[2]):
    j["seeded_files"][p] = {"origin_hash": "0" * 64, "path": p}
json.dump(j, open(f, "w"), indent=2)
PY
age "$T/ev" .claude/hooks/stop-checks.sh
commit "$T/ev" evilrecords
out=$(run "$T/ev" --apply); check "outside record paths: apply exits 0" 0 $?
contains "outside record path: ignored" "GONE      ../evil  (record path is outside the project or under a symlink; ignored)" "$out"
contains "absolute record path: ignored" "GONE      $T/abs-file  (record path is outside the project or under a symlink; ignored)" "$out"
check "outside record path: file kept" "keep" "$(cat "$T/evil")"
check "absolute record path: file kept" "keep" "$(cat "$T/abs-file")"

# Item 1 (the blocker): a customised file whose record and base copy were rewritten to match it is not proven unmodified.
# customise <dir> <path>: a local edit, then the record and the base copy rewritten from it (what regen-harness.sh and the re-baseline do).
customise() {
  if [ "$2" = .claude/settings.json ]; then
    python3 - "$1/$2" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
j["x-project"] = "kept"
json.dump(j, open(sys.argv[1], "w"), indent=2)
PY
  else
    printf '# customised by the project\n' >>"$1/$2"
  fi
  rehash "$1" "$2"
  cp "$1/$2" "$1/.claude/.harness-base/$2"
}
seed "$T/bk" nestjs
for f in .claude/settings.json lefthook.yml .claude/ci-gates.sh; do customise "$T/bk" "$f"; done
commit "$T/bk" customised
out=$(run "$T/bk")
for f in .claude/settings.json lefthook.yml .claude/ci-gates.sh; do
  contains "customised $f with forged record and base: MODIFIED" "MODIFIED  $f  (not identical to any released template; treated as edited)" "$out"
  mkdir -p "$T/bk-before/$(dirname "$f")"; cp "$T/bk/$f" "$T/bk-before/$f"
done
out=$(run "$T/bk" --apply); check "customised files: apply exits 1" 1 $?
for f in .claude/settings.json lefthook.yml .claude/ci-gates.sh; do
  check "customised $f is byte-identical after apply" "$(sha "$T/bk-before/$f")" "$(sha "$T/bk/$f")"
done
check "customised settings.json: sidecar written" 1 "$(find "$T/bk/.claude" -name 'settings.json.templatecentral-new' | wc -l | tr -d ' ')"
check "customised lefthook.yml: sidecar equals the template" "$(sha "$ROOT/skills/scaffold/shared/template-ts/lefthook.yml")" "$(sha "$T/bk/lefthook.yml.templatecentral-new")"
check "customised ci-gates.sh: sidecar equals the template" "$(sha "$ROOT/skills/scaffold/shared/template/.claude/ci-gates.sh")" "$(sha "$T/bk/.claude/ci-gates.sh.templatecentral-new")"
# control: the same project with the files left as seeded and aged to a released version is replaced
seed "$T/bkc" nestjs
age "$T/bkc" lefthook.yml
age "$T/bkc" .claude/ci-gates.sh
commit "$T/bkc" aged
out=$(run "$T/bkc" --apply); check "control, released files: apply exits 0" 0 $?
check "control: lefthook.yml replaced" "$(sha "$ROOT/skills/scaffold/shared/template-ts/lefthook.yml")" "$(sha "$T/bkc/lefthook.yml")"
# fail closed: no list, nothing is proven
mv "$PRIST" "$PRIST.off"
out=$(run "$T/rec")
contains "no pristine list: fails closed to MODIFIED" "MODIFIED  scripts/test-budget.sh  (pristine-hashes.txt is missing; cannot prove it unmodified)" "$out"
absent "no pristine list: nothing is REPLACE" "REPLACE   scripts/test-budget.sh" "$out"
mv "$PRIST.off" "$PRIST"
# a project seeded by an older version that is not on the list gets a sidecar, never a replace
seed "$T/old" nestjs
printf '# a version before the list\n' >>"$T/old/scripts/test-budget.sh"
commit "$T/old" oldversion
out=$(run "$T/old" --apply)
contains "older seed not on the list: MODIFIED" "MODIFIED  scripts/test-budget.sh  (not identical to any released template; treated as edited)" "$out"
check "older seed not on the list: file kept" 1 "$(grep -c '^# a version before the list$' "$T/old/scripts/test-budget.sh")"

# Item 3: settings.json waits while new hooks land; the output says so and gives the next step.
seed "$T/wm" nestjs
age "$T/wm" .claude/hooks/stop-checks.sh
customise "$T/wm" .claude/settings.json
commit "$T/wm" waiting
out=$(run "$T/wm" --apply); check "waiting settings.json: exits 1" 1 $?
contains "waiting settings.json: block present" "WAITING FOR MERGE: .claude/settings.json was kept as it is." "$out"
contains "waiting settings.json: names the written hook" ".claude/hooks/stop-checks.sh" "$(printf '%s\n' "$out" | grep '^WAITING')"
contains "waiting settings.json: says the checks fail until the merge" "verify-harness.sh and the live check above fail" "$out"
contains "waiting settings.json: gives the next step" "Next: merge .claude/settings.json.templatecentral-new into .claude/settings.json structurally" "$out"
contains "waiting settings.json: the live check still ran" "live check:" "$out"
absent "control, clean apply: no waiting block" "WAITING FOR MERGE" "$(run "$T/c")"

# Item 5: the recorded version is bumped only when nothing waits for a merge.
PV=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$PLUG/.claude-plugin/plugin.json" | head -n 1)
setver() { python3 - "$1/.claude/harness.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
j["templatecentral_version"] = "0.0.1"
json.dump(j, open(sys.argv[1], "w"), indent=2)
PY
}
recver() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['templatecentral_version'])" "$1/.claude/harness.json"; }
seed "$T/vc" nestjs
age "$T/vc" .claude/hooks/stop-checks.sh
setver "$T/vc"
commit "$T/vc" ver
run "$T/vc" --apply >/dev/null
check "control, nothing waits: version bumped to the plugin version" "$PV" "$(recver "$T/vc")"
seed "$T/vm" nestjs
age "$T/vm" .claude/hooks/stop-checks.sh
printf 'edit\n' >>"$T/vm/.claude/hooks/protect-files.sh"
setver "$T/vm"
commit "$T/vm" ver
out=$(run "$T/vm" --apply)
check "a file waits: version stays as it was" "0.0.1" "$(recver "$T/vm")"
contains "a file waits: the run says the version is not bumped" "version not bumped: 1 file(s) wait for merge" "$out"
contains "a file waits: AGENTS.md marker is named as the project's" "The refresh does not edit AGENTS.md: its line-1 marker and the version line are yours" "$out"
absent "control: no 'not bumped' line when nothing waits" "version not bumped" "$(run "$T/c")"

# Item 8: plan notes where a seeded file lands next to the project's own CI or hook manager.
seed "$T/n1" nestjs
rm "$T/n1/.github/dependabot.yml" "$T/n1/lefthook.yml" "$T/n1/sonar-project.properties"
mkdir -p "$T/n1/.githooks"
printf 'name: own\n' >"$T/n1/.github/workflows/own.yml"
commit "$T/n1" own
out=$(run "$T/n1")
contains "own CI: a CI file added next to it is noted" "note: .github/dependabot.yml will be added next to the project's own CI (.github/workflows/own.yml); review it before you commit." "$out"
contains "other hook manager: lefthook.yml is noted" "note: lefthook.yml will be added but the project already uses another git-hook manager (.githooks)" "$out"
contains "sonar-project.properties: noted, stays seeded" "note: sonar-project.properties is seeded as a file only; it runs no scanner." "$out"
contains "sonar-project.properties: still an ADD" "ADD       sonar-project.properties" "$out"
seed "$T/n2" nestjs
rm "$T/n2/.github/dependabot.yml" "$T/n2/lefthook.yml"
commit "$T/n2" plain
out=$(run "$T/n2")
absent "control, no own CI: no CI note" "next to the project's own CI" "$out"
absent "control, no other hook manager: no hook note" "another git-hook manager" "$out"

# Pristine list: destination paths. The generator maps a manifest path to the project path like tc-copy.sh does.
GENS="$ROOT/skills/migrate/general/gen-pristine-hashes.sh"
G="$T/gen"
mkdir -p "$G/skills/migrate/general" "$G/skills/scaffold/shared/template-ci/github-ts/.github/workflows" "$G/skills/scaffold/shared/template-ci/azure/azure-pipelines" "$G/skills/scaffold/shared/template-ci/azure-ts" "$G/skills/scaffold/shared/template-late/docs" "$G/skills/scaffold/shared/template/.claude"
cp "$GENS" "$G/skills/migrate/general/gen-pristine-hashes.sh"
SH_G="$G/skills/scaffold/shared"
printf 'old ci\n' >"$SH_G/template-ci/github-ts/.github/workflows/ci.yml"
printf 'old gates\n' >"$SH_G/template-ci/azure/azure-pipelines/gates.yml"
printf 'old pipeline\n' >"$SH_G/template-ci/azure-ts/azure-pipelines.yml"
printf 'old doc __TC_NAME__\n' >"$SH_G/template-late/docs/title.md"
printf 'old gate script\n' >"$SH_G/template/.claude/gate.sh"
printf '%s\n' \
  'template-ci/github-ts/.github/workflows/ci.yml 644 - -' \
  'template-ci/azure/azure-pipelines/gates.yml 644 - -' \
  'template-ci/azure-ts/azure-pipelines.yml 644 - -' \
  'template-late/docs/title.md 644 __TC_NAME__ -' \
  'template/.claude/gate.sh 755 - -' >"$SH_G/template.manifest"
(cd "$G" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm one && git tag v7.0.0)
out=$(bash "$G/skills/migrate/general/gen-pristine-hashes.sh" 2>&1); check "generator: runs on a tagged fixture" 0 $?
GL="$G/skills/migrate/general/pristine-hashes.txt"
for want in .github/workflows/ci.yml azure-pipelines/gates.yml azure-pipelines.yml .claude/gate.sh; do
  check "generator: lists the project path $want" 1 "$(cut -f3 "$GL" | grep -cx -- "$want")"
done
check "generator: no path keeps its tree name" 0 "$(cut -f3 "$GL" | grep -cE '^(template|github-|azure-ts/|azure/)')"
check "generator: placeholder file is left out" 0 "$(cut -f3 "$GL" | grep -c 'title.md')"
out=$(bash "$G/skills/migrate/general/gen-pristine-hashes.sh" --check 2>&1); check "generator: --check passes on a fresh list" 0 $?
sed 's|\t\.github/workflows/ci.yml$|\tgithub-ts/.github/workflows/ci.yml|' "$GL" >"$GL.bad" && mv "$GL.bad" "$GL"
out=$(bash "$G/skills/migrate/general/gen-pristine-hashes.sh" --check 2>&1); check "generator: --check fails on a list with a tree-prefixed path" 1 $?
bash "$G/skills/migrate/general/gen-pristine-hashes.sh" >/dev/null 2>&1
# the real list: every CI path it holds is a path tc-copy.sh writes
mkdir -p "$T/cpaths/g" "$T/cpaths/a"
TC_STACK=nestjs TC_PART=base bash "$COPY" "$T/cpaths/g" >/dev/null 2>&1; TC_STACK=nestjs TC_PART=ci TC_CI=github bash "$COPY" "$T/cpaths/g" >/dev/null 2>&1
TC_STACK=nestjs TC_PART=base bash "$COPY" "$T/cpaths/a" >/dev/null 2>&1; TC_STACK=nestjs TC_PART=ci TC_CI=azure bash "$COPY" "$T/cpaths/a" >/dev/null 2>&1
TC_STACK=fastapi TC_PART=base bash "$COPY" "$T/cpaths/f" >/dev/null 2>&1 || { mkdir -p "$T/cpaths/f"; TC_STACK=fastapi TC_PART=base bash "$COPY" "$T/cpaths/f" >/dev/null 2>&1; }
TC_STACK=fastapi TC_PART=ci TC_CI=github bash "$COPY" "$T/cpaths/f" >/dev/null 2>&1
TC_STACK=fastapi TC_PART=ci TC_CI=azure bash "$COPY" "$T/cpaths/f" >/dev/null 2>&1
REALL="$ROOT/skills/migrate/general/pristine-hashes.txt"
miss=$(cut -f3 "$REALL" | grep -E '^(\.github/|azure-pipelines)' | sort -u | while IFS= read -r p; do
  [ -f "$T/cpaths/g/$p" ] || [ -f "$T/cpaths/a/$p" ] || [ -f "$T/cpaths/f/$p" ] || echo "$p"; done)
check "real list: every CI path is one tc-copy.sh writes" "" "$miss"
check "real list: has the CI workflow path" 1 "$(cut -f3 "$REALL" | sort -u | grep -cx '.github/workflows/ci.yml')"
# a pristine CI file gets REPLACE, an edited one MODIFIED, using the generated list
cp "$GL" "$PRIST"
seed "$T/ci1" nestjs
printf 'old ci\n' >"$T/ci1/.github/workflows/ci.yml"
commit "$T/ci1" oldci
out=$(run "$T/ci1")
contains "pristine old ci.yml: REPLACE" "REPLACE" "$(printf '%s\n' "$out" | grep -F '.github/workflows/ci.yml')"
printf 'old ci\n# local edit\n' >"$T/ci1/.github/workflows/ci.yml"
commit "$T/ci1" editedci
out=$(run "$T/ci1")
contains "edited ci.yml: MODIFIED" "MODIFIED  .github/workflows/ci.yml" "$out"

exit $fail

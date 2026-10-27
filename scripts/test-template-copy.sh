#!/usr/bin/env bash
# scripts/test-template-copy.sh — tests for the scaffold template trees and the copy
# instruction that installs them (skills/scaffold/shared/harness-kit.md, Step 0).
#
# Usage: bash scripts/test-template-copy.sh   (run from anywhere; needs git, python3)
#
# The copy and refuse-if-exists snippets are extracted from the kit markdown and executed, so
# the tests exercise the instruction an agent runs, not a copy of it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$REPO_ROOT/skills/scaffold"
SHARED="$SK/shared"
MANIFEST="$SHARED/template.manifest"
KIT_INDEX="$SHARED/harness-kit.md"
T=$(mktemp -d)
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# snippet <file> <heading regex> <n> — the nth ```bash fence after the first heading that matches.
snippet() {
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
head, want = re.compile(sys.argv[2]), int(sys.argv[3])
start = next((i for i, l in enumerate(lines) if head.match(l)), None)
if start is None:
    sys.exit(3)
seen = 0
i = start + 1
while i < len(lines) and not re.match(r"^## ", lines[i]):
    if lines[i].strip() == "```bash":
        seen += 1
        j = i + 1
        while lines[j].strip() != "```":
            j += 1
        if seen == want:
            print("\n".join(lines[i + 1:j]))
            sys.exit(0)
        i = j
    i += 1
sys.exit(4)
PY
}

# render <snippet-text> <target> <selector> — substitute <skill-dir> and <target> byte for byte
# (no sed, so any character in a path arrives untouched) and set the SEL line.
render() {
  printf '%s\n' "$1" | python3 -c '
import sys
sk, tgt, sel = sys.argv[1:]
out = []
for line in sys.stdin.read().split("\n"):
    out.append("SEL=\"" + sel + "\"" if line.startswith("SEL=") else line)
sys.stdout.write("\n".join(out).replace("<skill-dir>", sk).replace("<target>", tgt))
' "$SK" "$2" "$3"
}

STEP0=$(snippet "$KIT_INDEX" '^## Step 0\b' 1) || STEP0=""
CI_SNIPPET=$(snippet "$SHARED/harness-kit-enforcement.md" '^## Step B3\b' 1) || CI_SNIPPET=""
check 1 "$([[ -n "$STEP0" && -n "$CI_SNIPPET" ]] && echo 1 || echo 0)" "copy instructions found in the kit markdown (Step 0, Step B3 CI)"

run_step0() { # run_step0 <target> <variant ts|py>
  bash -c "$(render "$STEP0" "$1" "template template-$2")" 2>&1
}
run_ci() { # run_ci <target> <variant ts|py> <host github|azure>
  local sel=template-ci/azure
  [[ "$3" == github ]] && sel="template-ci/github-$2"
  bash -c "$(render "$CI_SNIPPET" "$1" "$sel")" 2>&1
}
run_copy() { # run_copy <target> <variant> <host> — Step 0, then the CI step; echoes output, returns the first failing exit code
  local out ec
  out=$(run_step0 "$1" "$2"); ec=$?
  printf '%s\n' "$out"
  [[ $ec -eq 0 ]] || return "$ec"
  run_ci "$1" "$2" "$3"
}

COMBOS="ts:github ts:azure py:github py:azure"

# ── manifest_matches_tree ────────────────────────────────────────────────────
# Every file under the template trees is listed, with its mode; nothing listed is missing.
python3 - "$SHARED" "$MANIFEST" > "$T/manifest.diff" <<'PY'
import os, sys
shared, manifest = sys.argv[1:]
trees = sorted(d for d in os.listdir(shared) if d.startswith("template") and os.path.isdir(os.path.join(shared, d)))
actual = {}
for tree in trees:
    for dp, _, fs in os.walk(os.path.join(shared, tree)):
        for f in fs:
            full = os.path.join(dp, f)
            rel = os.path.relpath(full, shared)
            actual[rel] = "%o" % (os.stat(full).st_mode & 0o777)
listed = {}
if os.path.isfile(manifest):
    for line in open(manifest, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            cols = line.split()
            if len(cols) != 4:
                print("BADLINE", line)
                continue
            if cols[0] in listed:
                print("DUPLICATE", cols[0])
            listed[cols[0]] = cols[1]
else:
    print("NOMANIFEST", manifest)
if not actual:
    print("EMPTYTREE", shared)
for p in sorted(actual):
    if p not in listed:
        print("UNLISTED", p)
    elif listed[p] != actual[p]:
        print("MODE", p, "manifest", listed[p], "tree", actual[p])
for p in sorted(listed):
    if p not in actual:
        print("MISSING", p)
PY
check "" "$(cat "$T/manifest.diff")" "manifest_matches_tree"

# ── template_sh_executable ───────────────────────────────────────────────────
bad=$(cd "$REPO_ROOT" && git ls-files -s -- 'skills/scaffold/shared/template*' | awk '$4 ~ /\.sh$/ && $1 != "100755" { print $4 }')
count=$(cd "$REPO_ROOT" && git ls-files -- 'skills/scaffold/shared/template*' | grep -c '\.sh$' || true)
check "" "$bad" "template_sh_executable: git mode 100755 for every template .sh"
check 1 "$([[ "$count" -gt 0 ]] && echo 1 || echo 0)" "template_sh_executable: at least one template .sh is tracked"

# ── copy_keeps_dotfiles (and exec bits, and no stray ci/ or template dir) ─────
for combo in $COMBOS; do
  v=${combo%%:*}; h=${combo##*:}
  tgt="$T/copy-$v-$h"; mkdir -p "$tgt"
  out=$(run_copy "$tgt" "$v" "$h"); ec=$?
  check 0 "$ec" "copy_keeps_dotfiles[$combo]: copy exits 0 ($out)"
  ci_file=.github/workflows/ci.yml; [[ $h == azure ]] && ci_file=azure-pipelines/templatecentral-gates.yml
  want=".claude/ci-gates.sh .claude/comment-hygiene-patterns.txt .claude/hooks/session-context.sh .claude/hooks/skill-usage-log.sh .claude/hooks/protect-files.sh .claude/verify-harness.sh .claude/regen-harness.sh .gitleaks.toml .lefthook/commit-msg.sh lefthook.yml $ci_file"
  missing=""
  for p in $want; do [[ -f "$tgt/$p" ]] || missing+=" $p"; done
  check "" "$missing" "copy_keeps_dotfiles[$combo]: dotfiles and CI file arrived"
  unexec=""
  while IFS= read -r p; do [[ -x "$tgt/$p" ]] || unexec+=" $p"; done < <(cd "$tgt" && find . -type f -name '*.sh' | sed 's|^\./||')
  check "" "$unexec" "template_sh_executable[$combo]: exec bits survive the copy"
  stray=""
  [[ -e "$tgt/ci" ]] && stray+=" ci"
  [[ -e "$tgt/template" || -e "$tgt/template-ts" || -e "$tgt/template-py" || -e "$tgt/template-ci" ]] && stray+=" template"
  check "" "$stray" "copy_keeps_dotfiles[$combo]: no stray directory in the target"
  other=ts; [[ $v == ts ]] && other=py
  hook=user-prompt-guard.py; [[ $v == ts ]] && hook=user-prompt-guard.cjs
  otherhook=user-prompt-guard.cjs; [[ $v == ts ]] && otherhook=user-prompt-guard.py
  check 1 "$([[ -f "$tgt/.claude/hooks/$hook" && ! -e "$tgt/.claude/hooks/$otherhook" ]] && echo 1 || echo 0)" "copy_keeps_dotfiles[$combo]: only the $v variant of user-prompt-guard arrived (not $other)"
done

# ── copy_refuses_existing_path ───────────────────────────────────────────────
tgt="$T/refuse"; mkdir -p "$tgt/.claude" "$tgt/azure-pipelines"
printf 'mine\n' > "$tgt/.gitleaks.toml"
printf 'mine\n' > "$tgt/.claude/ci-gates.sh"
out=$(run_copy "$tgt" ts github); ec=$?
check 1 "$([[ $ec -ne 0 ]] && echo 1 || echo 0)" "copy_refuses_existing_path: nonzero exit"
case "$out" in *".gitleaks.toml"*".claude/ci-gates.sh"* | *".claude/ci-gates.sh"*".gitleaks.toml"*) r=names ;; *) r="$out" ;; esac
check names "$r" "copy_refuses_existing_path: names every clashing path"
check "mine" "$(cat "$tgt/.gitleaks.toml")" "copy_refuses_existing_path: existing file untouched"
check 2 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "copy_refuses_existing_path: nothing written"
# a clash on the chosen host's CI path refuses; the other host's CI path does not
tgt="$T/refuse-ci"; mkdir -p "$tgt/azure-pipelines"; printf 'mine\n' > "$tgt/azure-pipelines/templatecentral-gates.yml"
run_step0 "$tgt" ts >/dev/null; check 0 $? "copy_refuses_existing_path: the CI file is not part of the Step 0 check"
if run_ci "$tgt" ts azure >/dev/null; then r=0; else r=1; fi
check 1 "$r" "copy_refuses_existing_path: Azure CI file clash refused by the CI step"
check "mine" "$(cat "$tgt/azure-pipelines/templatecentral-gates.yml")" "copy_refuses_existing_path: existing CI file untouched"
rm -rf "$T/refuse-ci-gh"; mkdir -p "$T/refuse-ci-gh/azure-pipelines"; printf 'mine\n' > "$T/refuse-ci-gh/azure-pipelines/templatecentral-gates.yml"
run_ci "$T/refuse-ci-gh" ts github >/dev/null; check 0 $? "copy_refuses_existing_path: Azure CI file does not block a GitHub CI copy"
# a clash on the other variant's hook does not block (only the chosen variant is seeded)
tgt="$T/refuse-variant"; mkdir -p "$tgt/.claude/hooks"; printf 'mine\n' > "$tgt/.claude/hooks/user-prompt-guard.py"
run_copy "$tgt" ts github >/dev/null; check 0 $? "copy_refuses_existing_path: other variant's file does not block"

# ── the guard fails closed ───────────────────────────────────────────────────
# alt_skill <name> — a writable copy of the shared trees; echoes its skill dir.
alt_skill() { rm -rf "$T/alt-$1"; mkdir -p "$T/alt-$1/scaffold"; cp -Rp "$SHARED" "$T/alt-$1/scaffold/shared"; echo "$T/alt-$1/scaffold"; }
# refuses <name> <skill-dir> <selector> <target> — Step 0 or CI snippet must exit nonzero and write nothing.
refuses() {
  local name=$1 sk=$2 sel=$3 tgt=$4 snip=$STEP0 out ec saved=$SK
  [[ "$sel" == template-ci/* ]] && snip=$CI_SNIPPET
  SK=$sk
  out=$(bash -c "$(render "$snip" "$tgt" "$sel")" 2>&1); ec=$?
  SK=$saved
  check 1 "$([[ $ec -ne 0 ]] && echo 1 || echo 0)" "$name: nonzero exit ($out)"
  check 0 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "$name: nothing copied"
}
sk=$(alt_skill nomanifest); rm "$sk/shared/template.manifest"; mkdir -p "$T/g1"
refuses copy_refuses_missing_manifest "$sk" "template template-ts" "$T/g1"
sk=$(alt_skill emptymanifest); : > "$sk/shared/template.manifest"; mkdir -p "$T/g2"
refuses copy_refuses_empty_manifest "$sk" "template template-ts" "$T/g2"
mkdir -p "$T/g3"
refuses copy_refuses_unmatched_selector "$SK" "template template-bogus" "$T/g3"
mkdir -p "$T/g3b"
refuses ci_copy_refuses_unmatched_selector "$SK" "template-ci/nope" "$T/g3b"
sk=$(alt_skill unlisted); printf 'x\n' > "$sk/shared/template/.claude/unlisted.txt"; mkdir -p "$T/g4"
refuses copy_refuses_file_missing_from_manifest "$sk" "template template-ts" "$T/g4"
sk=$(alt_skill ghost); printf 'template/.claude/ghost.sh 755 - -\n' >> "$sk/shared/template.manifest"; mkdir -p "$T/g5"
refuses copy_refuses_manifest_line_without_file "$sk" "template template-ts" "$T/g5"
sk=$(alt_skill ci-nomanifest); rm "$sk/shared/template.manifest"; mkdir -p "$T/g6"
refuses ci_copy_refuses_missing_manifest "$sk" "template-ci/github-ts" "$T/g6"
# a symlinked top-level directory is refused, and nothing is written through it
mkdir -p "$T/g7" "$T/elsewhere"; ln -s "$T/elsewhere" "$T/g7/.claude"
refuses copy_refuses_symlinked_top_level_dir "$SK" "template template-ts" "$T/g7"
check 0 "$(find "$T/elsewhere" -type f | wc -l | tr -d ' ')" "copy_refuses_symlinked_top_level_dir: nothing written through the link"
mkdir -p "$T/g8" "$T/elsewhere2"; ln -s "$T/elsewhere2" "$T/g8/.github"
refuses ci_copy_refuses_symlinked_top_level_dir "$SK" "template-ci/github-ts" "$T/g8"
mkdir -p "$T/g9" "$T/elsewhere3"; ln -s "$T/elsewhere3" "$T/g9/.lefthook"
refuses copy_refuses_symlinked_lefthook_dir "$SK" "template template-ts" "$T/g9"
# a symlink anywhere in the dirname chain is refused
mkdir -p "$T/g11/.claude" "$T/elsewhere4"; ln -s "$T/elsewhere4" "$T/g11/.claude/hooks"
refuses copy_refuses_nested_symlink_dir "$SK" "template template-ts" "$T/g11"
check 0 "$(find "$T/elsewhere4" -type f | wc -l | tr -d ' ')" "copy_refuses_nested_symlink_dir: nothing written through the link"
mkdir -p "$T/g12/.github" "$T/elsewhere5"; ln -s "$T/elsewhere5" "$T/g12/.github/workflows"
refuses ci_copy_refuses_nested_symlink_dir "$SK" "template-ci/github-ts" "$T/g12"

# the fences behave the same under zsh (which does not split $SEL), and a refusal never kills the caller's shell
if command -v zsh >/dev/null 2>&1; then
  tgt="$T/z1"; mkdir -p "$tgt"
  out=$(zsh -c "$(render "$STEP0" "$tgt" "template template-ts")" 2>&1); ec=$?
  check 0 "$ec" "zsh_step0_success_exits_0 ($out)"
  check 1 "$([[ -x "$tgt/.claude/hooks/session-context.sh" && -f "$tgt/.gitleaks.toml" && -f "$tgt/lefthook.yml" ]] && echo 1 || echo 0)" "zsh_step0_success_copies"
  out=$(zsh -c "$(render "$STEP0" "$tgt" "template template-ts")" 2>&1); ec=$?
  check 1 "$([[ $ec -ne 0 ]] && echo 1 || echo 0)" "zsh_step0_refusal_exits_nonzero"
  tgt="$T/z2"; mkdir -p "$tgt"
  out=$(zsh -c "$(render "$CI_SNIPPET" "$tgt" "template-ci/azure")" 2>&1); ec=$?
  check 0 "$ec" "zsh_ci_success_exits_0 ($out)"
  check 1 "$([[ -f "$tgt/azure-pipelines/templatecentral-gates.yml" ]] && echo 1 || echo 0)" "zsh_ci_success_copies"
  tgt="$T/z3"; mkdir -p "$tgt"; printf 'mine\n' > "$tgt/.gitleaks.toml"
  out=$(zsh -c "$(render "$STEP0" "$tgt" "template template-ts")
echo CALLER_SURVIVED" 2>&1)
  check 1 "$([[ "$out" == *CALLER_SURVIVED* && "$out" == *Refusing* ]] && echo 1 || echo 0)" "zsh_refusal_leaves_caller_shell_alive"
  check 1 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "zsh_refusal_copies_nothing"
  out=$(bash -c "$(render "$STEP0" "$tgt" "template template-ts")
echo CALLER_SURVIVED" 2>&1)
  check 1 "$([[ "$out" == *CALLER_SURVIVED* ]] && echo 1 || echo 0)" "bash_refusal_leaves_caller_shell_alive"
elif [[ "${CI:-}" == true ]]; then
  FAIL=$((FAIL + 1)); echo "FAIL: zsh is not installed but CI=true; the zsh guard tests must run in CI"
else
  echo "SKIP: zsh tests (zsh not installed)"
fi

# a real top-level directory that already holds other files is fine
mkdir -p "$T/g10/.claude"; printf 'mine\n' > "$T/g10/.claude/own.txt"
out=$(run_step0 "$T/g10" ts); check 0 "$?" "copy_allows_existing_directory_with_other_files ($out)"
check mine "$(cat "$T/g10/.claude/own.txt")" "copy_allows_existing_directory_with_other_files: own file kept"
# ── round 3: hostile paths, unsubstituted values, stop line, odd trees ────────
STOPLINE="STOP: do not rm or overwrite anything; report this to the user"
mkdir -p "$T/h"
hostile_ok() { # hostile_ok <dir name> — Step 0 must copy into the literal path and run nothing
  local name=$1 tgt out ec
  tgt="$T/h/$name"; mkdir -p "$tgt"
  out=$(run_step0 "$tgt" ts); ec=$?
  check 0 "$ec" "hostile_target[$name]: exits 0 ($out)"
  check 1 "$([[ -f "$tgt/.gitleaks.toml" && -x "$tgt/.claude/hooks/session-context.sh" ]] && echo 1 || echo 0)" "hostile_target[$name]: copied into the literal path"
}
hostile_ok 'sp ace'
hostile_ok "q'uote"
# shellcheck disable=SC2016  # the dollar signs are part of the hostile directory names
hostile_ok 'dollar$x'
# shellcheck disable=SC2016
hostile_ok 'home$HOME'
hostile_ok 'dq"uote'
hostile_ok 'back\slash'
hostile_ok 'semi;colon'
hostile_ok "bt\`touch $T/PWNED\`x"
hostile_ok "sub\$(touch $T/PWNED2)x"
check 0 "$([[ -e "$T/PWNED" || -e "$T/PWNED2" ]] && echo 1 || echo 0)" "hostile_target: no command in a path was executed"
# a path with a newline is refused, not truncated
tgt="$T/h/new
line"; mkdir -p "$tgt"
out=$(run_step0 "$tgt" ts); ec=$?
check 1 "$([[ $ec -ne 0 ]] && echo 1 || echo 0)" "hostile_target[newline]: refused"
check 0 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "hostile_target[newline]: nothing copied"
# the same through the CI block
tgt="$T/h/ci'q\$x"; mkdir -p "$tgt"; out=$(run_ci "$tgt" ts github); check 0 "$?" "hostile_target[ci]: exits 0 ($out)"
check 1 "$([[ -f "$tgt/.github/workflows/ci.yml" ]] && echo 1 || echo 0)" "hostile_target[ci]: copied into the literal path"

# empty, unsubstituted and non-directory values are refused
refuses_raw() { # refuses_raw <name> <snippet text> <expected message substring>
  local out ec
  out=$(bash -c "$2" 2>&1); ec=$?
  check 1 "$([[ $ec -ne 0 ]] && echo 1 || echo 0)" "$1: nonzero exit"
  check 1 "$([[ "$out" == *"$3"* ]] && echo 1 || echo 0)" "$1: message names the cause ($out)"
  check 1 "$([[ "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "$1: ends with the stop line"
}
refuses_raw guard_refuses_empty_target "$(render "$STEP0" "" "template template-ts")" "target"
refuses_raw guard_refuses_unsubstituted_target "$(printf '%s\n' "$STEP0" | python3 -c 'import sys; print(sys.stdin.read().replace("<skill-dir>", sys.argv[1]))' "$SK")" "not substituted"
refuses_raw guard_refuses_unsubstituted_skill_dir "$(printf '%s\n' "$STEP0" | python3 -c 'import sys; print(sys.stdin.read().replace("<target>", sys.argv[1]))' "$T/h")" "not substituted"
refuses_raw guard_refuses_empty_skill_dir "$(printf '%s\n' "$STEP0" | python3 -c 'import sys; print(sys.stdin.read().replace("<skill-dir>/shared", "").replace("<target>", sys.argv[1]))' "$T/h")" "skill"
: > "$T/regular-file"
refuses_raw guard_refuses_regular_file_target "$(render "$STEP0" "$T/regular-file" "template template-ts")" "existing directory"
refuses_raw guard_refuses_missing_target "$(render "$STEP0" "$T/no/such/dir" "template template-ts")" "existing directory"
refuses_raw guard_refuses_clash_with_stop_line "$(mkdir -p "$T/c1" && : > "$T/c1/.gitleaks.toml" && render "$STEP0" "$T/c1" "template template-ts")" ".gitleaks.toml"

# a cp failure stops the step, says files may be partly written, and ends with the stop line
if [[ "$(id -u)" != 0 ]]; then
  tgt="$T/ro"; mkdir -p "$tgt"; chmod a-w "$tgt"
  refuses_raw copy_failure_stops_with_partial_write_warning "$(render "$STEP0" "$tgt" "template template-ts")" "partly written"
  chmod u+w "$tgt"
else
  echo "SKIP: cp failure test (running as root)"
fi

# a symlink or an empty directory inside a template tree is refused, because find -type f misses both
sk=$(alt_skill treelink); ln -s /etc/hosts "$sk/shared/template/zz-link"; mkdir -p "$T/o1"
refuses tree_with_symlink_is_refused "$sk" "template template-ts" "$T/o1"
sk=$(alt_skill treeempty); mkdir -p "$sk/shared/template/zz-empty"; mkdir -p "$T/o2"
refuses tree_with_empty_dir_is_refused "$sk" "template template-ts" "$T/o2"

# a read-only plugin cache must not leave read-only directories in the project
sk=$(alt_skill readonly); chmod -R a-w "$sk/shared/template" "$sk/shared/template-ts"; tgt="$T/o3"; mkdir -p "$tgt"
saved=$SK; SK=$sk; out=$(run_step0 "$tgt" ts); ec=$?; SK=$saved
check 0 "$ec" "copy_from_read_only_cache_exits_0 ($out)"
check 1 "$([[ -w "$tgt/.claude" && -w "$tgt/.claude/hooks" && -w "$tgt/.claude/hooks/session-context.sh" && -w "$tgt/lefthook.yml" ]] && echo 1 || echo 0)" "copy_from_read_only_cache_leaves_writable_paths"
chmod -R u+w "$sk/shared"

# the two guards are the same script apart from the SEL and WHAT lines
norm() { printf '%s\n' "$1" | grep -v '^SEL=\|^WHAT=\|^cp ' ; }
check "$(norm "$STEP0")" "$(norm "$CI_SNIPPET")" "guards_identical: Step 0 and Step B3 carry the same guard"

# seed-neither CI path leaves exactly what 6.x left: the golden tree minus ci-gates.sh and the CI file
NEITHER=$(snippet "$SHARED/harness-kit-enforcement.md" '^## Step B3\b' 2) || NEITHER=""
tgt="$T/o4"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null
check 1 "$([[ -n "$NEITHER" ]] && echo 1 || echo 0)" "seed_neither: the removal fence exists in Step B3"
bash -c "$(render "$NEITHER" "$tgt" "none")" >/dev/null 2>&1
want=$(python3 - "$MANIFEST" "$REPO_ROOT/tests/golden/nextjs-github.sha256" <<'PY'
import sys
manifest, golden = sys.argv[1:]
gold = {l.split("  ", 1)[1].strip() for l in open(golden) if l.strip() and not l.startswith("#")}
out = set()
for l in open(manifest):
    if l.strip() and not l.startswith("#"):
        p = l.split()[0]
        for tree in ("template/", "template-ts/"):
            if p.startswith(tree):
                out.add(p[len(tree):])
print("\n".join(sorted((out & gold) - {".claude/ci-gates.sh"})))
PY
)
check "$want" "$(cd "$tgt" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)" "seed_neither: tree equals the 6.x seed-neither file set"

# every template .sh parses
bad=""; while IFS= read -r f; do bash -n "$f" 2>/dev/null || bad+=" $f"; done < <(find "$SHARED" -path '*/template*' -name '*.sh')
check "" "$bad" "template_sh_parses: bash -n over every template .sh"

# ── dist_keeps_templates ─────────────────────────────────────────────────────
dist="$T/dist/agents-skills"
bash "$REPO_ROOT/scripts/build-agents-dist.sh" "$SK/.." "$dist" >/dev/null 2>&1
check 0 $? "dist_keeps_templates: build-agents-dist.sh runs"
python3 - "$SHARED" "$dist/scaffold/shared" > "$T/dist.diff" <<'PY'
import os, sys
src, dist = sys.argv[1:]
def listing(root):
    out = {}
    for tree in sorted(d for d in os.listdir(root) if d.startswith("template") and os.path.isdir(os.path.join(root, d))):
        for dp, _, fs in os.walk(os.path.join(root, tree)):
            for f in fs:
                full = os.path.join(dp, f)
                out[os.path.relpath(full, root)] = (os.stat(full).st_mode & 0o777, open(full, "rb").read())
    return out
a, b = (listing(src) if os.path.isdir(src) else {}), (listing(dist) if os.path.isdir(dist) else {})
if not a:
    print("EMPTY source templates")
for p in sorted(a):
    if p not in b:
        print("LOST", p)
    elif a[p][0] != b[p][0]:
        print("MODE", p, "%o" % a[p][0], "%o" % b[p][0])
    elif a[p][1] != b[p][1]:
        print("CONTENT", p)
for p in sorted(b):
    if p not in a:
        print("EXTRA", p)
if not os.path.isfile(os.path.join(dist, "template.manifest")):
    print("LOST template.manifest")
PY
check "" "$(cat "$T/dist.diff")" "dist_keeps_templates"
# the dist copy works the same way: copy from the dist skill dir
tgt="$T/dist-copy"; mkdir -p "$tgt"
(SK="$dist/scaffold"; run_step0 "$tgt" ts) >/dev/null 2>&1
[[ -x "$tgt/.claude/hooks/session-context.sh" && -f "$tgt/.gitleaks.toml" ]]; check 0 $? "dist_keeps_templates: copy from the dist layout keeps dotfiles and exec bits"

echo "test-template-copy: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

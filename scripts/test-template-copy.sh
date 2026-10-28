#!/usr/bin/env bash
# scripts/test-template-copy.sh — tests for the scaffold template trees and the copy
# instruction that installs them (skills/scaffold/shared/harness-kit.md, Step 0).
#
# Usage: bash scripts/test-template-copy.sh   (run from anywhere; needs git, python3)
#
# The copy and refuse-if-exists snippets are extracted from the kit markdown (and from the stack
# source-files.md that copies a stack's own tree) and executed, so the tests exercise the instruction
# an agent runs, not a copy of it.
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
# snap <dir> — every path under <dir> of any type (files, directories, symlinks), sorted; a refusal test compares it before and after
snap() { (cd "$1" && find . 2>/dev/null | LC_ALL=C sort); }
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

# render_sc <snippet-text> <target> <stack> <ci> [part] — substitute <skill-dir> and <target> byte for byte
# (no sed, so any character in a path arrives untouched) and set the STACK and CI lines.
render_sc() {
  printf '%s\n' "$1" | python3 -c '
import sys
sk, tgt, stack, ci = sys.argv[1:5]
part = sys.argv[5] if len(sys.argv) > 5 else None
out = []
for line in sys.stdin.read().split("\n"):
    if line.startswith("STACK="):
        line = "STACK=" + stack
    elif line.startswith("CI="):
        line = "CI=" + ci
    elif line.startswith("PART=") and part is not None:
        line = "PART=" + part
    out.append(line)
sys.stdout.write("\n".join(out).replace("<skill-dir>", sk).replace("<target>", tgt))
' "$SK" "$2" "$3" "$4" ${5+"$5"}
}

# render <snippet-text> <target> <selector> — a template-tree selector mapped onto STACK and CI:
# "template template-ts" is nextjs, "template template-py" fastapi, "template-ci/github-ts" nextjs on
# GitHub, "template-ci/github-py" fastapi on GitHub, "template-ci/azure" nextjs on Azure.
render() {
  local stack=bogus ci=""
  case "$3" in
    "template template-ts") stack=nextjs ;;
    "template template-py") stack=fastapi ;;
    template-ci/github-ts) stack=nextjs; ci=github ;;
    template-ci/github-py) stack=fastapi; ci=github ;;
    template-ci/azure) stack=nextjs; ci=azure ;;
    template-ci/nope) stack=nextjs; ci=nope ;;
  esac
  render_sc "$1" "$2" "$stack" "$ci"
}

STEP0=$(snippet "$KIT_INDEX" '^## Step 0\b' 1) || STEP0=""
# Step B3 runs Step 0's script with PART=ci: the CI and CI=none runs are that fence with its PART line set.
CI_SNIPPET=$(printf '%s\n' "$STEP0" | sed 's/^PART=base$/PART=ci/')
check 1 "$([[ -n "$STEP0" ]] && echo 1 || echo 0)" "the copy script is found in the kit markdown (Step 0)"

stack_of() { if [[ "$1" == py ]]; then echo fastapi; else echo nextjs; fi; }
run_step0() { # run_step0 <target> <variant ts|py>
  bash -c "$(render_sc "$STEP0" "$1" "$(stack_of "$2")" "")" 2>&1
}
run_ci() { # run_ci <target> <variant ts|py> <host github|azure> — Step B3 requires Step 0's lefthook.yml, so run Step 0 first when it is absent
  [[ -f "$1/lefthook.yml" ]] || bash -c "$(render_sc "$STEP0" "$1" "$(stack_of "$2")" "")" >/dev/null 2>&1
  bash -c "$(render_sc "$CI_SNIPPET" "$1" "$(stack_of "$2")" "$3")" 2>&1
}
run_part() { # run_part <target> <stack> <part> [ci] — the Step 0 script with another PART
  bash -c "$(render_sc "$STEP0" "$1" "$2" "${4:-}" "$3")" 2>&1
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
bad=$(cd "$REPO_ROOT" && git ls-files -s -- 'skills/scaffold/shared/template*' 'skills/scaffold/nextjs/template*' | awk '$4 ~ /\.sh$/ && $1 != "100755" { print $4 }')
count=$(git -C "$REPO_ROOT" ls-files -- 'skills/scaffold/shared/template*' 'skills/scaffold/nextjs/template*' | grep -c '\.sh$' || true)
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
before=$(snap "$tgt")
out=$(run_copy "$tgt" ts github); ec=$?
check 1 "$([[ $ec -ne 0 ]] && echo 1 || echo 0)" "copy_refuses_existing_path: nonzero exit"
case "$out" in *".gitleaks.toml"*".claude/ci-gates.sh"* | *".claude/ci-gates.sh"*".gitleaks.toml"*) r=names ;; *) r="$out" ;; esac
check names "$r" "copy_refuses_existing_path: names every clashing path"
check "mine" "$(cat "$tgt/.gitleaks.toml")" "copy_refuses_existing_path: existing file untouched"
check "$before" "$(snap "$tgt")" "copy_refuses_existing_path: nothing written"
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
# the refusal tests compare every path, so a directory created before the clash check shows up
tgt="$T/refuse-snap"; mkdir -p "$tgt"; : > "$tgt/.gitleaks.toml"; before=$(snap "$tgt")
# shellcheck disable=SC2016  # the patterns are literal script text, not expansions
mut=${STEP0/'[ -z "$clash" ] || stop'/'mkdir -p "$TGT/.zz"; [ -z "$clash" ] || stop'}
check 1 "$([[ "$mut" != "$STEP0" ]] && echo 1 || echo 0)" "snap_catches_a_directory_made_before_the_clash_check: the mutation applies"
bash -c "$(render "$mut" "$tgt" "template template-ts")" >/dev/null 2>&1
check 1 "$([[ "$before" != "$(snap "$tgt")" ]] && echo 1 || echo 0)" "snap_catches_a_directory_made_before_the_clash_check: a file-only count would not"

# ── the guard fails closed ───────────────────────────────────────────────────
# alt_skill <name> — a writable copy of the shared trees; echoes its skill dir.
alt_skill() { rm -rf "$T/alt-$1"; mkdir -p "$T/alt-$1/scaffold"; cp -Rp "$SHARED" "$T/alt-$1/scaffold/shared"; echo "$T/alt-$1/scaffold"; }
# refuses <name> <skill-dir> <selector> <target> — Step 0 or CI snippet must exit nonzero and write nothing.
refuses() {
  local name=$1 sk=$2 sel=$3 tgt=$4 snip=$STEP0 out ec saved=$SK
  [[ "$sel" == template-ci/* ]] && snip=$CI_SNIPPET
  local before
  before=$(snap "$tgt")
  SK=$sk
  out=$(bash -c "$(render "$snip" "$tgt" "$sel")" 2>&1); ec=$?
  SK=$saved
  check 1 "$([[ $ec -ne 0 ]] && echo 1 || echo 0)" "$name: nonzero exit ($out)"
  check "$before" "$(snap "$tgt")" "$name: nothing copied"
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
check . "$(snap "$T/elsewhere")" "copy_refuses_symlinked_top_level_dir: nothing written through the link"
mkdir -p "$T/g8" "$T/elsewhere2"; ln -s "$T/elsewhere2" "$T/g8/.github"
refuses ci_copy_refuses_symlinked_top_level_dir "$SK" "template-ci/github-ts" "$T/g8"
mkdir -p "$T/g9" "$T/elsewhere3"; ln -s "$T/elsewhere3" "$T/g9/.lefthook"
refuses copy_refuses_symlinked_lefthook_dir "$SK" "template template-ts" "$T/g9"
# a symlink anywhere in the dirname chain is refused
mkdir -p "$T/g11/.claude" "$T/elsewhere4"; ln -s "$T/elsewhere4" "$T/g11/.claude/hooks"
refuses copy_refuses_nested_symlink_dir "$SK" "template template-ts" "$T/g11"
check . "$(snap "$T/elsewhere4")" "copy_refuses_nested_symlink_dir: nothing written through the link"
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
  zsh -c "$(render "$STEP0" "$tgt" "template template-ts")" >/dev/null 2>&1
  out=$(zsh -c "$(render "$CI_SNIPPET" "$tgt" "template-ci/azure")" 2>&1); ec=$?
  check 0 "$ec" "zsh_ci_success_exits_0 ($out)"
  check 1 "$([[ -f "$tgt/azure-pipelines/templatecentral-gates.yml" ]] && echo 1 || echo 0)" "zsh_ci_success_copies"
  tgt="$T/z3"; mkdir -p "$tgt"; printf 'mine\n' > "$tgt/.gitleaks.toml"; before=$(snap "$tgt")
  out=$(zsh -c "$(render "$STEP0" "$tgt" "template template-ts")
echo CALLER_SURVIVED" 2>&1)
  check 1 "$([[ "$out" == *CALLER_SURVIVED* && "$out" == *Refusing* ]] && echo 1 || echo 0)" "zsh_refusal_leaves_caller_shell_alive"
  check "$before" "$(snap "$tgt")" "zsh_refusal_copies_nothing"
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
# ── hostile paths, unsubstituted values, stop line, odd trees ─────────────────
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
check . "$(snap "$tgt")" "hostile_target[newline]: nothing copied"
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

# an unwritable project root is caught by the pre-check, before any write
if [[ "$(id -u)" != 0 ]]; then
  tgt="$T/ro"; mkdir -p "$tgt"; chmod a-w "$tgt"
  refuses_raw readonly_root_refused_before_writing "$(render "$STEP0" "$tgt" "template template-ts")" "not writable"
  chmod u+w "$tgt"
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

# the STACK, CI, PART and WHAT lines differ between runs; norm drops them so a text comparison sees the script alone
norm() { printf '%s\n' "$1" | grep -v '^STACK=\|^CI=\|^PART=\|^WHAT=' ; }
check 1 "$([[ "$(norm "$STEP0")" == "$(norm "$CI_SNIPPET")" ]] && echo 1 || echo 0)" "single_script: the PART=ci run is Step 0's script with the PART line set"

# the PART=ci CI=none path leaves exactly what 6.x left: the golden tree minus ci-gates.sh and the CI file
NEITHER=$CI_SNIPPET
tgt="$T/o4"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null
# shellcheck disable=SC2016  # the anchor is literal script text
check 1 "$([[ "$NEITHER" == *'rm -f -- "$TGT/$gate"'* ]] && echo 1 || echo 0)" "ci_none: the removal branch exists in the Step 0 script"
bash -c "$(render_sc "$NEITHER" "$tgt" nextjs none)" >/dev/null 2>&1
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
check "$want" "$(cd "$tgt" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)" "ci_none: tree equals the 6.x file set without a CI host"

# ── write only the listed paths, derive trees from STACK and CI ───────────────
modeof() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# stack_check <stack> <ci> <guard file> <other guard file> — the right hook variant and CI file arrive
for sc in nestjs:cjs nextjs:cjs vite-react:cjs fastapi:py; do
  st=${sc%%:*}; ext=${sc##*:}; other=py; [[ $ext == py ]] && other=cjs
  for ci in github azure; do
    tgt="$T/st-$st-$ci"; mkdir -p "$tgt"
    out=$(bash -c "$(render_sc "$STEP0" "$tgt" "$st" "")" 2>&1); e1=$?
    out2=$(bash -c "$(render_sc "$CI_SNIPPET" "$tgt" "$st" "$ci")" 2>&1); e2=$?
    check 00 "$e1$e2" "stack_derives_trees[$st/$ci]: both fences exit 0 ($out $out2)"
    check 1 "$([[ -f "$tgt/.claude/hooks/user-prompt-guard.$ext" && ! -e "$tgt/.claude/hooks/user-prompt-guard.$other" ]] && echo 1 || echo 0)" "stack_derives_trees[$st/$ci]: the right user-prompt-guard (.$ext, not .$other)"
    if [[ $ci == azure ]]; then
      check 1 "$([[ -f "$tgt/azure-pipelines/templatecentral-gates.yml" && ! -e "$tgt/.github" ]] && echo 1 || echo 0)" "stack_derives_trees[$st/$ci]: the Azure file only"
    else
      want=0; [[ $ext == py ]] && want=1
      check "$want" "$(grep -c 'pyright' "$tgt/.github/workflows/ci.yml")" "stack_derives_trees[$st/$ci]: the GitHub workflow for this stack (pyright job only for fastapi)"
      check 1 "$([[ ! -e "$tgt/azure-pipelines" ]] && echo 1 || echo 0)" "stack_derives_trees[$st/$ci]: no Azure file"
    fi
  done
done
refuses_raw unknown_stack_refused "$(mkdir -p "$T/u1" && render_sc "$STEP0" "$T/u1" "rails" "")" "unknown STACK"
check . "$(snap "$T/u1")" "unknown_stack_refused: nothing copied"
refuses_raw empty_stack_refused "$(mkdir -p "$T/u2" && render_sc "$STEP0" "$T/u2" "" "")" "unknown STACK"
refuses_raw unknown_ci_refused "$(mkdir -p "$T/u3" && render_sc "$CI_SNIPPET" "$T/u3" "nextjs" "gitlab")" "unknown CI"
refuses_raw empty_ci_in_ci_step_refused "$(mkdir -p "$T/u4" && render_sc "$CI_SNIPPET" "$T/u4" "nextjs" "")" "unknown CI"
check ". ." "$(snap "$T/u3") $(snap "$T/u4")" "unknown_ci_refused: nothing copied"

# the project root and existing directories keep their modes; the user's own files are not touched
for m in 0700 2775 0750; do
  tgt="$T/mode-$m"; mkdir -p "$tgt/.claude" "$tgt/.github"; chmod "$m" "$tgt" "$tgt/.claude"
  before=$(modeof "$tgt"); beforec=$(modeof "$tgt/.claude")
  out=$(run_step0 "$tgt" ts); run_ci "$tgt" ts github >/dev/null
  check "$before" "$(modeof "$tgt")" "root_mode_kept[$m]: the project root mode is unchanged ($out)"
  check "$beforec" "$(modeof "$tgt/.claude")" "root_mode_kept[$m]: an existing .claude keeps its mode"
done
tgt="$T/ownfile"; mkdir -p "$tgt/.claude"; printf 'mine\n' > "$tgt/.claude/own.txt"; chmod 0400 "$tgt/.claude/own.txt"
run_step0 "$tgt" ts >/dev/null
check 400 "$(modeof "$tgt/.claude/own.txt")" "user_file_mode_kept: a 0400 file in an existing .claude stays 0400"
# a regular file where a directory is needed refuses with nothing written
for name in .claude .lefthook; do
  tgt="$T/notdir$name"; mkdir -p "$tgt"; printf 'mine\n' > "$tgt/$name"
  before=$(snap "$tgt")
  refuses_raw "not_a_directory_refused[$name]" "$(render_sc "$STEP0" "$tgt" nextjs "")" "not a directory"
  check "$before" "$(snap "$tgt")" "not_a_directory_refused[$name]: only the user's file is there"
done
tgt="$T/notdirgh"; mkdir -p "$tgt"; printf 'mine\n' > "$tgt/.github"
refuses_raw "not_a_directory_refused[.github via CI]" "$(render_sc "$CI_SNIPPET" "$tgt" nextjs github)" "not a directory"
# a read-only template source still yields the manifest modes in the target
sk=$(alt_skill rosrc); chmod -R a-w "$sk/shared/template" "$sk/shared/template-ts"; tgt="$T/romodes"; mkdir -p "$tgt"
saved=$SK; SK=$sk; run_step0 "$tgt" ts >/dev/null; SK=$saved
bad=""
while read -r p m _; do
  case "$p" in template/*) f=${p#template/} ;; template-ts/*) f=${p#template-ts/} ;; *) continue ;; esac
  [[ "$(modeof "$tgt/$f")" == "$m" ]] || bad+=" $f"
done < <(grep -v '^#' "$MANIFEST")
check "" "$bad" "read_only_source_yields_manifest_modes"
check 1 "$([[ -w "$tgt/.claude/hooks" ]] && echo 1 || echo 0)" "read_only_source_leaves_directories_writable"
chmod -R u+w "$sk/shared"

# a failure after the pre-checks reports the state: cp and chmod are stubbed to fail on a chosen call
mkdir -p "$T/stubs"
# shellcheck disable=SC2016  # the stubs are scripts; their variables expand when they run
printf '#!/usr/bin/env bash\nn=$(cat "$STUB_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_COUNT"\nif [ "$n" -eq "$STUB_FAIL_AT" ]; then echo "stub cp failure" >&2; exit 1; fi\nexec /bin/cp "$@"\n' > "$T/stubs/cp"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nn=$(cat "$STUB_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_COUNT"\nif [ "$n" -eq "$STUB_FAIL_AT" ]; then echo "stub chmod failure" >&2; exit 1; fi\nexec /bin/chmod "$@"\n' > "$T/stubs/chmod"
chmod +x "$T/stubs/cp" "$T/stubs/chmod"
for which in cp chmod; do
  tgt="$T/stub-$which"; mkdir -p "$tgt"; rm -f "$T/stub-count"
  out=$(PATH="$T/stubs:$PATH" STUB_COUNT="$T/stub-count" STUB_FAIL_AT=3 bash -c "$(render_sc "$STEP0" "$tgt" nextjs "")" 2>&1); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out" == *"partly written"* && "$out" == *"may also have written"* || "$out" == *"chmod failed"* ]] && echo 1 || echo 0)" "stub_${which}_failure_reports_state: nonzero and says so ($out)"
  check 1 "$([[ "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "stub_${which}_failure_reports_state: ends with the stop line"
  written=$(cd "$tgt" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
  listed_out=$(printf '%s\n' "$out" | sed -n '/^Files already written:/,/^STOP/p' | grep -v '^Files already\|^STOP' | grep . | LC_ALL=C sort)
  if [[ $which == cp ]]; then
    # the third cp is the failed one: two files are listed and two are on disk (cp wrote nothing for the third)
    check "$written" "$listed_out" "stub_cp_failure_reports_state: the reported files are exactly the files on disk"
  else
    # the third chmod fails after its file was copied: the file is listed, so listed equals on disk
    check "$written" "$listed_out" "stub_chmod_failure_reports_state: a file whose chmod failed is still listed"
  fi
done

# hostile skill-dir paths
# shellcheck disable=SC2016  # the dollar sign is part of the hostile directory name
for name in 'sp ace' "q'uote" 'dollar$x' 'dq"uote' 'back\slash'; do
  alt="$T/sk-$name"; mkdir -p "$alt"; cp -Rp "$SHARED" "$alt/shared"
  tgt="$T/hs-target"; rm -rf "$tgt"; mkdir -p "$tgt"
  saved=$SK; SK=$alt; out=$(run_step0 "$tgt" ts); ec=$?; SK=$saved
  check 0 "$ec" "hostile_skill_dir[$name]: exits 0 ($out)"
  check 1 "$([[ -f "$tgt/.gitleaks.toml" ]] && echo 1 || echo 0)" "hostile_skill_dir[$name]: copied"
done
alt="$T/sk-bt\`touch $T/PWNED3\`x"; mkdir -p "$alt"; cp -Rp "$SHARED" "$alt/shared"; tgt="$T/hs-target2"; mkdir -p "$tgt"
saved=$SK; SK=$alt; run_step0 "$tgt" ts >/dev/null; SK=$saved
check 0 "$([[ -e "$T/PWNED3" ]] && echo 1 || echo 0)" "hostile_skill_dir: no command in a skill-dir path was executed"

# a relative target that starts with a dash
mkdir -p "$T/rel/-proj"
out=$(cd "$T/rel" && bash -c "$(render_sc "$STEP0" "-proj" nextjs "")" 2>&1); ec=$?
check 0 "$ec" "dash_target: exits 0 ($out)"
check 1 "$([[ -f "$T/rel/-proj/.gitleaks.toml" && -x "$T/rel/-proj/.claude/hooks/session-context.sh" ]] && echo 1 || echo 0)" "dash_target: copied into -proj"

# PART=ci CI=none removes the gate script only when it is the template's byte for byte
NEITHER=$CI_SNIPPET
tgt="$T/sn1"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null
printf '# local edit\n' >> "$tgt/.claude/ci-gates.sh"
refuses_raw ci_none_keeps_a_modified_script "$(render_sc "$NEITHER" "$tgt" nextjs none)" "differs from the template"
check 1 "$(grep -c 'local edit' "$tgt/.claude/ci-gates.sh")" "ci_none_keeps_a_modified_script: the user's edit survives"
refuses_raw ci_none_refuses_unsubstituted_target "$(printf '%s\n' "$NEITHER" | python3 -c 'import sys; print(sys.stdin.read().replace("<skill-dir>", sys.argv[1]))' "$SK")" "not substituted"
refuses_raw ci_none_refuses_missing_dir "$(render_sc "$NEITHER" "$T/no/such" nextjs none)" "existing directory"
tgt="$T/sn2"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null
out=$(bash -c "$(render_sc "$NEITHER" "$tgt" nextjs none)" 2>&1); ec=$?
check 0 "$ec" "ci_none_removes_an_identical_script ($out)"
check 1 "$([[ ! -e "$tgt/.claude/ci-gates.sh" && -e "$tgt/.claude/verify-harness.sh" ]] && echo 1 || echo 0)" "ci_none_removes_an_identical_script: only ci-gates.sh is gone"
# on a project that has no gate script, PART=ci CI=none is a no-op
tgt="$T/sn3"; mkdir -p "$tgt/.claude"; printf 'mine\n' > "$tgt/own.txt"; before=$(snap "$tgt")
out=$(bash -c "$(render_sc "$NEITHER" "$tgt" nextjs none)" 2>&1); ec=$?
check 0 "$ec" "ci_none_without_a_gate_script: exits 0 ($out)"
check 1 "$([[ "$out" == *"Nothing to remove"* ]] && echo 1 || echo 0)" "ci_none_without_a_gate_script: prints Nothing to remove ($out)"
check "$before" "$(snap "$tgt")" "ci_none_without_a_gate_script: nothing written"

# the refusal for a manifest/tree mismatch names the offending files
sk=$(alt_skill dsstore); printf 'x\n' > "$sk/shared/template/.DS_Store"; mkdir -p "$T/ds"
saved=$SK; SK=$sk; out=$(bash -c "$(render "$STEP0" "$T/ds" "template template-ts")" 2>&1); SK=$saved
check 1 "$([[ "$out" == *".DS_Store"* ]] && echo 1 || echo 0)" "mismatch_refusal_names_the_file ($out)"

# ── PART=ci CI=none symlinks, pre-checks, PART, hostile-name matrix ──────────────
refuses_dir() { # refuses_dir <name> <snippet text> <message substring> <dir that must stay empty of new files>
  refuses_raw "$1" "$2" "$3"
}
# PART=ci CI=none follows no symlink
tgt="$T/sl1"; mkdir -p "$tgt" "$T/sl1-real/.claude"; cp "$SHARED/template/.claude/ci-gates.sh" "$T/sl1-real/.claude/ci-gates.sh"
ln -s "$T/sl1-real/.claude" "$tgt/.claude"
refuses_raw ci_none_refuses_symlinked_claude_dir "$(render_sc "$NEITHER" "$tgt" nextjs none)" "symlink"
check 1 "$([[ -f "$T/sl1-real/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "ci_none_refuses_symlinked_claude_dir: the link target is untouched"
tgt="$T/sl2"; mkdir -p "$tgt/.claude"; cp "$SHARED/template/.claude/ci-gates.sh" "$T/sl2-real.sh"; ln -s "$T/sl2-real.sh" "$tgt/.claude/ci-gates.sh"
refuses_raw ci_none_refuses_symlinked_gate "$(render_sc "$NEITHER" "$tgt" nextjs none)" "symlink"
check 1 "$([[ -f "$T/sl2-real.sh" && -L "$tgt/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "ci_none_refuses_symlinked_gate: the link and its target are untouched"
tgt="$T/sl3"; mkdir -p "$tgt/.claude"; ln -s "$T/does-not-exist" "$tgt/.claude/ci-gates.sh"
refuses_raw ci_none_refuses_dangling_symlink_gate "$(render_sc "$NEITHER" "$tgt" nextjs none)" "symlink"
check 1 "$([[ -L "$tgt/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "ci_none_refuses_dangling_symlink_gate: the link is still there"
tgt="$T/sl4"; mkdir -p "$tgt/.claude/ci-gates.sh"
refuses_raw ci_none_refuses_a_directory_gate "$(render_sc "$NEITHER" "$tgt" nextjs none)" "not a regular file"

# an unwritable existing directory is caught before anything is written
if [[ "$(id -u)" != 0 ]]; then
  tgt="$T/prew"; mkdir -p "$tgt/.lefthook"; chmod 0555 "$tgt/.lefthook"
  before=$(snap "$tgt")
  refuses_raw prewrite_check_refuses_unwritable_dir "$(render_sc "$STEP0" "$tgt" nextjs "")" "not writable"
  check "$before" "$(snap "$tgt")" "prewrite_check_refuses_unwritable_dir: zero files written"
  chmod u+w "$tgt/.lefthook"
  sk=$(alt_skill unreadable); chmod 000 "$sk/shared/template/.gitleaks.toml"; mkdir -p "$T/prer"
  saved=$SK; SK=$sk
  refuses_raw prewrite_check_refuses_unreadable_source "$(render_sc "$STEP0" "$T/prer" nextjs "")" "unreadable"
  SK=$saved
  check . "$(snap "$T/prer")" "prewrite_check_refuses_unreadable_source: zero files written"
  chmod 644 "$sk/shared/template/.gitleaks.toml"
fi

# PART and CI must agree with the fence they are in
for combo in "STEP0|github|base|CI must stay empty" "STEP0||ci|unknown CI" "CI|github|base|CI must stay empty" "CI||ci|unknown CI" "STEP0||weird|unknown PART" "CI|github|weird|unknown PART"; do
  IFS='|' read -r which ci part msg <<<"$combo"
  snip=$STEP0; [[ $which == CI ]] && snip=$CI_SNIPPET
  tgt="$T/part-$which-$part-$ci"; mkdir -p "$tgt"; before=$(snap "$tgt")
  refuses_raw "part_mismatch[$which ci=$ci part=$part]" "$(render_sc "$snip" "$tgt" nextjs "$ci" "$part")" "$msg"
  check "$before" "$(snap "$tgt")" "part_mismatch[$which ci=$ci part=$part]: nothing written"
done

# a relative path that starts with a dash is not read as an option
mkdir -p "$T/dsh/-sk"; cp -Rp "$SHARED" "$T/dsh/-sk/shared"; mkdir -p "$T/dsh/-tgt"
saved=$SK; SK="-sk"
out=$(cd "$T/dsh" && bash -c "$(render_sc "$STEP0" "-tgt" nextjs "")" 2>&1); ec=$?
SK=$saved
check 0 "$ec" "dash_skill_dir_and_target: exits 0 ($out)"
check 1 "$([[ -f "$T/dsh/-tgt/.gitleaks.toml" ]] && echo 1 || echo 0)" "dash_skill_dir_and_target: copied"

# hostile names for the skill dir and the target, both stacks, both fences
NL_=$'\n'
# shellcheck disable=SC2016  # the dollar signs and backticks are part of the hostile names
HOSTILE=("sp ace" "q'uote" 'dollar$x$(touch PWN)' 'back`touch PWN`tick' 'dq"uote' $'ta\tb' "new${NL_}line" 'hash#tag' 'amp&semi;' 'ünï-日本' '*?[a]' '~' '{a,b}' 'bang!' '  lead and trail  ')
run="$T/run"; mkdir -p "$run"
for stack in nextjs fastapi; do
  rm -rf "$T/ref0" "$T/refci"; mkdir -p "$T/ref0" "$T/refci"
  bash -c "$(render_sc "$STEP0" "$T/ref0" "$stack" "")" >/dev/null 2>&1
  bash -c "$(render_sc "$STEP0" "$T/refci" "$stack" "")" >/dev/null 2>&1
  bash -c "$(render_sc "$CI_SNIPPET" "$T/refci" "$stack" github)" >/dev/null 2>&1
  n0=$(find "$T/ref0" -type f | wc -l | tr -d ' '); nci=$(( $(find "$T/refci" -type f | wc -l | tr -d ' ') - n0 ))
  for kind in TGT SK; do
    for name in "${HOSTILE[@]}"; do
      for fence in STEP0 CI; do
        rm -rf "$T/hm"; mkdir -p "$T/hm"
        if [[ $kind == TGT ]]; then
          tgt="$T/hm/$name"; mkdir -p "$tgt"; sk=$SK
        else
          sk="$T/hm/$name"; mkdir -p "$sk"; cp -Rp "$SHARED" "$sk/shared"; tgt="$T/hm-tgt"; rm -rf "$tgt"; mkdir -p "$tgt"
        fi
        saved=$SK; SK=$sk
        if [[ $fence == STEP0 ]]; then snip=$STEP0; ci=""; want=$n0; else snip=$CI_SNIPPET; ci=github; want=$nci; fi
        if [[ $fence == CI ]]; then
          (cd "$run" && bash -c "$(render_sc "$STEP0" "$tgt" "$stack" "")" >/dev/null 2>&1)
          want=$((n0 + nci))
        fi
        out=$(cd "$run" && bash -c "$(render_sc "$snip" "$tgt" "$stack" "$ci")" 2>&1); ec=$?
        SK=$saved
        got=$(find "$tgt" -type f | wc -l | tr -d ' ')
        label="hostile_${kind}[$stack/$fence/$(printf '%q' "$name")]"
        if [[ "$name" == *$'\n'* ]]; then
          check 1 "$([[ $ec -ne 0 && "$(snap "$tgt")" == . ]] && echo 1 || echo 0)" "$label: refused with nothing written"
        else
          check 1 "$([[ $ec -eq 0 && $got == "$want" ]] && echo 1 || echo 0)" "$label: copied $want files (exit $ec, got $got: $out)"
        fi
        check 0 "$([[ -e "$run/PWN" || -e "$T/PWN" || -e "$tgt/PWN" ]] && echo 1 || echo 0)" "$label: no command ran"
      done
    done
  done
done
# relative names that need the ./ prefix or a literal tilde
for name in '-dash' '~'; do
  for fence in STEP0 CI; do
    rm -rf "$run"; mkdir -p "$run/$name"
    snip=$STEP0; ci=""
    if [[ $fence == CI ]]; then
      snip=$CI_SNIPPET; ci=github
      (cd "$run" && bash -c "$(render_sc "$STEP0" "$name" nextjs "")" >/dev/null 2>&1)
    fi
    out=$(cd "$run" && bash -c "$(render_sc "$snip" "$name" nextjs "$ci")" 2>&1); ec=$?
    check 1 "$([[ $ec -eq 0 && -n "$(find "$run/$name" -type f | head -1)" ]] && echo 1 || echo 0)" "hostile_relative_target[$name/$fence]: copied ($out)"
  done
done

# ── shipped STACK line is empty, and Step B3 must match Step 0 ────────────────
raw_render() { # raw_render <snippet text> <target> — substitute only <skill-dir> and <target>; STACK, CI and PART stay as shipped
  printf '%s\n' "$1" | python3 -c 'import sys; print(sys.stdin.read().replace("<skill-dir>", sys.argv[1]).replace("<target>", sys.argv[2]))' "$SK" "$2"
}
mkdir -p "$T/ship0" "$T/ship1"
refuses_raw shipped_step0_fence_refuses_until_stack_is_set "$(raw_render "$STEP0" "$T/ship0")" "unknown STACK"
check . "$(snap "$T/ship0")" "shipped_step0_fence_refuses_until_stack_is_set: nothing written"
run_step0 "$T/ship1" ts >/dev/null
before=$(snap "$T/ship1")
refuses_raw shipped_ci_fence_refuses_until_stack_is_set "$(raw_render "$CI_SNIPPET" "$T/ship1")" "unknown STACK"
check "$before" "$(snap "$T/ship1")" "shipped_ci_fence_refuses_until_stack_is_set: nothing written"
# a B3 STACK that differs from Step 0's is refused
mkdir -p "$T/mis1"; run_step0 "$T/mis1" ts >/dev/null
before=$(snap "$T/mis1")
refuses_raw ci_stack_differs_from_step0 "$(render_sc "$CI_SNIPPET" "$T/mis1" fastapi github)" "does not match"
check "$before" "$(snap "$T/mis1")" "ci_stack_differs_from_step0: nothing written"
# B3 without Step 0's lefthook.yml is refused too
mkdir -p "$T/mis2"
refuses_raw ci_without_step0_refused "$(render_sc "$CI_SNIPPET" "$T/mis2" nextjs github)" "does not match"
check . "$(snap "$T/mis2")" "ci_without_step0_refused: nothing written"

# ── searchable directories, rm and mkdir failures, relative targets, manifest message ──
if [[ "$(id -u)" != 0 ]]; then
  # a directory that is writable but not searchable is refused before any write
  for pair in ".lefthook:0666" ".claude:0600"; do
    d=${pair%%:*}; m=${pair##*:}
    tgt="$T/nosearch$d"; mkdir -p "$tgt/$d"; chmod "$m" "$tgt/$d"
    before=$(snap "$tgt")
    refuses_raw "prewrite_check_refuses_unsearchable_dir[$d $m]" "$(render_sc "$STEP0" "$tgt" nextjs "")" "not writable"
    chmod 0755 "$tgt/$d"
    check "$before" "$(snap "$tgt")" "prewrite_check_refuses_unsearchable_dir[$d $m]: zero files written"
  done
  # PART=ci CI=none reports a failed rm and leaves the gate in place
  tgt="$T/rmfail"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null; chmod 0555 "$tgt/.claude"
  refuses_raw ci_none_reports_a_failed_rm "$(render_sc "$NEITHER" "$tgt" nextjs none)" "rm failed"
  check 1 "$([[ -f "$tgt/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "ci_none_reports_a_failed_rm: the gate is still there"
  chmod 0755 "$tgt/.claude"
fi
# a failing mkdir after the pre-checks stops with the state report (mkdir stubbed to fail)
printf '#!/usr/bin/env bash\necho "stub mkdir failure" >&2\nexit 1\n' > "$T/stubs/mkdir"; chmod +x "$T/stubs/mkdir"
for which in STEP0 CI; do
  tgt="$T/mkfail-$which"; mkdir -p "$tgt"
  snip=$STEP0; ci=""
  if [[ $which == CI ]]; then snip=$CI_SNIPPET; ci=github; bash -c "$(render_sc "$STEP0" "$tgt" nextjs "")" >/dev/null 2>&1; fi
  before=$(snap "$tgt")
  out=$(PATH="$T/stubs:$PATH" bash -c "$(render_sc "$snip" "$tgt" nextjs "$ci")" 2>&1); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out" == *"mkdir failed"* && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "mkdir_failure_stops[$which]: nonzero, names mkdir, ends with the stop line ($out)"
  check "$before" "$(snap "$tgt")" "mkdir_failure_stops[$which]: nothing was written"
done
# a relative target is prefixed with ./ (the refusal for a missing one shows it), and a copy into -proj lands in ./-proj
for which in STEP0 CI; do
  snip=$STEP0; ci=""; [[ $which == CI ]] && { snip=$CI_SNIPPET; ci=github; }
  out=$(cd "$T" && bash -c "$(render_sc "$snip" "-nodir" nextjs "$ci")" 2>&1)
  check 1 "$([[ "$out" == *"./-nodir is not an existing directory"* ]] && echo 1 || echo 0)" "relative_target_gets_dot_slash[$which] ($out)"
done
mkdir -p "$T/relp/-proj"
(cd "$T/relp" && bash -c "$(render_sc "$STEP0" "-proj" nextjs "")" >/dev/null 2>&1 && bash -c "$(render_sc "$CI_SNIPPET" "-proj" nextjs github)" >/dev/null 2>&1)
check 1 "$([[ -f "$T/relp/-proj/.gitleaks.toml" && -f "$T/relp/-proj/.github/workflows/ci.yml" ]] && echo 1 || echo 0)" "relative_target_dash_proj: both fences wrote into ./-proj"
# the manifest check has its own message
sk=$(alt_skill mfmissing); rm "$sk/shared/template.manifest"; mkdir -p "$T/mf1"
saved=$SK; SK=$sk
refuses_raw missing_manifest_message "$(render_sc "$STEP0" "$T/mf1" nextjs "")" "missing or empty"
SK=$saved
sk=$(alt_skill mfempty); : > "$sk/shared/template.manifest"; mkdir -p "$T/mf2"
saved=$SK; SK=$sk
refuses_raw empty_manifest_message "$(render_sc "$STEP0" "$T/mf2" nextjs "")" "missing or empty"
SK=$saved

# ── nextjs stack trees ───────────────────────────────────────────────────────
# The stack's own verbatim files: <stack>/template (copied at Step 1) and <stack>/template-agents
# (AGENTS.md, copied at Step 6), listed in <stack>/template.manifest. The copy is kit Step 0's guard
# run with PART=stack and PART=agents, so the stack fences are that fence with the PART line set.
NX="$SK/nextjs"
STACK_SNIPPET=$(printf '%s\n' "$STEP0" | sed 's/^PART=base$/PART=stack/')
AGENTS_SNIPPET=$(printf '%s\n' "$STEP0" | sed 's/^PART=base$/PART=agents/')
check 1 "$([[ "$STACK_SNIPPET" == *"PART=stack"* && "$AGENTS_SNIPPET" == *"PART=agents"* ]] && echo 1 || echo 0)" "stack copy fences derive from kit Step 0 (PART=stack, PART=agents)"
# the nextjs docs run kit Step 0 for each part, with the stack named
nxdoc=$(cat "$NX/source-files.md")
# shellcheck disable=SC2016  # the backticks are literal text in the docs, not command substitution
check 1 "$([[ "$nxdoc" == *'`STACK=nextjs` in its fence and `PART=stack`'* && "$nxdoc" == *'`STACK=nextjs` in its fence and `PART=base`'* && "$nxdoc" == *'`STACK=nextjs` in its fence and `PART=agents`'* ]] && echo 1 || echo 0)" "nextjs_docs_run_kit_step0_for_stack_base_and_agents"
# the nextjs docs carry no copy of the guard: the kit index holds the only one
check 0 "$(grep -c 'TC_GUARD' "$NX/source-files.md" | awk -F: '{ s += $2 } END { print s + 0 }')" "nextjs_docs_hold_no_second_guard"
run_stack() { bash -c "$(render_sc "$STACK_SNIPPET" "$1" nextjs "")" 2>&1; }   # run_stack <target>
run_agents() { bash -c "$(render_sc "$AGENTS_SNIPPET" "$1" nextjs "")" 2>&1; } # run_agents <target>
count_files() { find "$1" -type f | wc -l | tr -d ' '; }
N_STACK=$(count_files "$NX/template")
N_AGENTS=$(count_files "$NX/template-agents")
check 1 "$([[ "$N_STACK" -gt 50 && "$N_AGENTS" -eq 1 ]] && echo 1 || echo 0)" "stack trees are not empty (template $N_STACK files, template-agents $N_AGENTS)"

# alt_nx <name> — a writable skill dir with an empty shared/ and a copy of the nextjs trees; echoes it.
alt_nx() { rm -rf "$T/altnx-$1"; mkdir -p "$T/altnx-$1/scaffold/shared"; cp -Rp "$NX" "$T/altnx-$1/scaffold/nextjs"; echo "$T/altnx-$1/scaffold"; }
# refuses_nx <name> <skill dir> <snippet text> <target> [stack] — the stack fence must exit nonzero, write nothing, and end with the stop line.
refuses_nx() {
  local name=$1 sk=$2 snip=$3 tgt=$4 stack=${5:-nextjs} out ec saved=$SK before
  before=$(snap "$tgt")
  SK=$sk
  out=$(bash -c "$(render_sc "$snip" "$tgt" "$stack" "")" 2>&1); ec=$?
  SK=$saved
  check 1 "$([[ $ec -ne 0 && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "$name: nonzero exit and the stop line ($out)"
  check "$before" "$(snap "$tgt")" "$name: nothing copied"
}

# ── nextjs_manifest_matches_tree ─────────────────────────────────────────────
# Every file under the stack's trees is listed with its mode, its placeholders and its seams.
stack_manifest_diff() { # stack_manifest_diff <stack dir>
  python3 - "$1" <<'PY'
import os, re, sys
root = sys.argv[1]
trees = ["template", "template-agents", "template-tail"]
actual = {}
for tree in trees:
    for dp, _, fs in os.walk(os.path.join(root, tree)):
        for f in fs:
            full = os.path.join(dp, f)
            data = open(full, "rb").read()
            actual[os.path.relpath(full, root)] = (
                "%o" % (os.stat(full).st_mode & 0o777),
                sorted(set(m.decode() for m in re.findall(rb"__TC_[A-Z0-9_]+__", data))),
                sorted(set(m.decode() for m in re.findall(rb"\[\[post-harness\]\]", data))),
            )
listed = {}
manifest = os.path.join(root, "template.manifest")
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
            listed[cols[0]] = (cols[1], [] if cols[2] == "-" else cols[2].split(","), [] if cols[3] == "-" else cols[3].split(","))
else:
    print("NOMANIFEST", manifest)
if not actual:
    print("EMPTYTREE", root)
for tree in trees:
    if not any(p.startswith(tree + "/") for p in actual):
        print("EMPTYTREE", tree)
for p in sorted(actual):
    if p not in listed:
        print("UNLISTED", p)
        continue
    if listed[p][0] != actual[p][0]:
        print("MODE", p, "manifest", listed[p][0], "tree", actual[p][0])
    if sorted(listed[p][1]) != actual[p][1]:
        print("PLACEHOLDERS", p, "manifest", listed[p][1], "file", actual[p][1])
    if sorted(listed[p][2]) != actual[p][2]:
        print("SEAMS", p, "manifest", listed[p][2], "file", actual[p][2])
for p in sorted(listed):
    if p not in actual:
        print("MISSING", p)
PY
}
check "" "$(stack_manifest_diff "$NX")" "nextjs_manifest_matches_tree"
sk=$(alt_nx mf-unlisted); printf 'x\n' > "$sk/nextjs/template/zz-unlisted.txt"
check 1 "$([[ "$(stack_manifest_diff "$sk/nextjs")" == *"UNLISTED template/zz-unlisted.txt"* ]] && echo 1 || echo 0)" "nextjs_manifest_matches_tree: an unlisted file is reported"
sk=$(alt_nx mf-ghost); printf 'template/ghost.txt 644 - -\n' >> "$sk/nextjs/template.manifest"
check 1 "$([[ "$(stack_manifest_diff "$sk/nextjs")" == *"MISSING template/ghost.txt"* ]] && echo 1 || echo 0)" "nextjs_manifest_matches_tree: a listed file without a file is reported"
sk=$(alt_nx mf-empty); rm -rf "$sk/nextjs/template" "$sk/nextjs/template-agents"
check 1 "$([[ "$(stack_manifest_diff "$sk/nextjs")" == *"EMPTYTREE"* ]] && echo 1 || echo 0)" "nextjs_manifest_matches_tree: an empty tree is reported"
sk=$(alt_nx mf-ph); python3 -c 'import sys; p=sys.argv[1]; t=open(p).read(); open(p,"w").write(t.replace("__TC_PROJECT_NAME__","__TC_OTHER_NAME__"))' "$sk/nextjs/template/package.json"
check 1 "$([[ "$(stack_manifest_diff "$sk/nextjs")" == *"PLACEHOLDERS template/package.json"* ]] && echo 1 || echo 0)" "nextjs_manifest_matches_tree: an undeclared placeholder is reported"

# ── placeholders_only_in_small_files ─────────────────────────────────────────
# A file that carries __TC_ tokens is read and edited by the model, so it stays small, and a stack has at most 5.
big_placeholders() { # big_placeholders <dir>... — one line per template file over 4 KB that carries a placeholder, then TOOMANY when the dirs together hold more than 5 such files
  python3 - "$@" <<'PY'
import os, sys
n = 0
for root in sys.argv[1:]:
    for dp, _, fs in os.walk(root):
        for f in fs:
            full = os.path.join(dp, f)
            data = open(full, "rb").read()
            if b"__TC_" in data:
                n += 1
                if len(data) >= 4096:
                    print("BIG", os.path.relpath(full, root), len(data))
if n > 5:
    print("TOOMANY", n, "placeholder files across", " ".join(sys.argv[1:]))
PY
}
# every shared tree plus the stack's own trees count together: a stack's project receives all of them
check "" "$(big_placeholders "$NX/template" "$NX/template-agents" "$SHARED"/template*)" "placeholders_only_in_small_files: nextjs with every shared tree"
check "" "$(big_placeholders "$SHARED"/template*)" "placeholders_only_in_small_files: shared"
rm -rf "$T/span-shared"; mkdir -p "$T/span-shared"; cp -Rp "$SHARED" "$T/span-shared/shared"; cp -Rp "$NX" "$T/span-shared/nextjs"
for f in template/.gitleaks.toml template/.claude/ci-gates.sh template-ts/lefthook.yml; do printf '__TC_X__\n' >> "$T/span-shared/shared/$f"; done
check 1 "$([[ "$(big_placeholders "$T/span-shared/nextjs/template" "$T/span-shared/nextjs/template-agents" "$T/span-shared"/shared/template*)" == *"TOOMANY 6"* ]] && echo 1 || echo 0)" "placeholders_only_in_small_files: 4 shared plus 2 stack files is over the limit per stack"
python3 -c 'import sys; open(sys.argv[1],"a").write("__TC_X__\n"+"x"*5000+"\n")' "$T/span-shared/shared/template-late/FUTURE.md"
check 1 "$([[ "$(big_placeholders "$T/span-shared"/shared/template-late)" == "BIG FUTURE.md"* ]] && echo 1 || echo 0)" "placeholders_only_in_small_files: a placeholder in a large template-late file is reported"
sk=$(alt_nx big-ph); python3 -c 'import sys; open(sys.argv[1],"a").write("// __TC_PROJECT_NAME__\n"+"x"*5000+"\n")' "$sk/nextjs/template/vitest.config.ts"
check 1 "$([[ "$(big_placeholders "$sk/nextjs/template")" == "BIG vitest.config.ts"* ]] && echo 1 || echo 0)" "placeholders_only_in_small_files: a placeholder in a file over 4 KB is reported"
sk=$(alt_nx many-ph); for f in .npmrc .prettierrc .gitignore .dockerignore .env.example tsconfig.json; do printf '__TC_X__\n' >> "$sk/nextjs/template/$f"; done
check 1 "$([[ "$(big_placeholders "$sk/nextjs/template")" == *"TOOMANY"* ]] && echo 1 || echo 0)" "placeholders_only_in_small_files: more than 5 placeholder files is reported"
sk=$(alt_nx span-ph); for f in .npmrc .prettierrc; do printf '__TC_X__\n' >> "$sk/nextjs/template/$f"; done; printf '__TC_Y__\n' > "$sk/nextjs/template-agents/zz-a.md"; printf '__TC_Z__\n' > "$sk/nextjs/template-agents/zz-b.md"
check 1 "$([[ "$(big_placeholders "$sk/nextjs/template" "$sk/nextjs/template-agents")" == *"TOOMANY 6"* ]] && echo 1 || echo 0)" "placeholders_only_in_small_files: 4 in template/ plus 2 in template-agents/ is over the limit per stack"

# ── no_leftover_placeholders ─────────────────────────────────────────────────
# After the copy and the substitution, grep -rn '__TC_' over the project is empty. The values come from tests/golden/placeholders.env.
substitute_placeholders() { # substitute_placeholders <dir> <env file>
  python3 - "$1" "$2" <<'PY'
import os, sys
root, env = sys.argv[1:]
values = {}
for line in open(env, encoding="utf-8"):
    line = line.rstrip("\n")
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        values[k] = v
for dp, _, fs in os.walk(root):
    for f in fs:
        full = os.path.join(dp, f)
        data = open(full, "rb").read()
        new = data
        for k, v in values.items():
            new = new.replace(("__TC_%s__" % k).encode(), v.encode())
        if new != data:
            open(full, "wb").write(new)
PY
}
tgt="$T/nlp"; mkdir -p "$tgt"
out=$(run_step0 "$tgt" ts); out2=$(run_ci "$tgt" ts github); out3=$(run_stack "$tgt"); out4=$(run_agents "$tgt"); out4+=$(run_part "$tgt" nextjs late)
check 1 "$([[ $(count_files "$tgt") -gt $((N_STACK + N_AGENTS)) ]] && echo 1 || echo 0)" "no_leftover_placeholders: the kit, CI and stack trees all copied ($out $out2 $out3 $out4)"
before=$(grep -rln '__TC_' "$tgt" | sed "s|^$tgt/||" | LC_ALL=C sort | tr '\n' ' ')
check "AGENTS.md docs/CONSTITUTION.md package.json " "$before" "no_leftover_placeholders: the placeholders are present before the substitution"
substitute_placeholders "$tgt" "$REPO_ROOT/tests/golden/placeholders.env"
check "" "$(grep -rn '__TC_' "$tgt" || true)" "no_leftover_placeholders: nothing is left after the substitution"
check 1 "$([[ "$(grep -c '"name": "PROJECT_NAME_PLACEHOLDER"' "$tgt/package.json")" == 1 && "$(grep -c '^# AGENTS.md — \[Project Name\]$' "$tgt/AGENTS.md")" == 1 ]] && echo 1 || echo 0)" "no_leftover_placeholders: the values landed where the golden holds them"
# every placeholder a manifest declares has a value in placeholders.env, so the substitution cannot skip one
declared=$(grep -v '^#' "$NX/template.manifest" | awk '$3 != "-" { print $3 }' | tr ',' '\n' | sed 's/^__TC_//; s/__$//' | LC_ALL=C sort -u)
valued=$(grep -v '^#' "$REPO_ROOT/tests/golden/placeholders.env" | grep . | cut -d= -f1 | LC_ALL=C sort -u)
check "" "$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$valued"))" "no_leftover_placeholders: every declared placeholder has a value in placeholders.env"

# ── copy_keeps_dotfiles, extended to the stack ───────────────────────────────
tgt="$T/nx-copy"; mkdir -p "$tgt"
out=$(run_stack "$tgt"); ec=$?
check 0 "$ec" "copy_keeps_dotfiles[nextjs]: stack copy exits 0 ($out)"
missing=""
for p in .dockerignore .env.example .gitignore .npmrc .prettierignore .prettierrc docker-entrypoint.sh package.json src/app/layout.tsx 'src/app/(public)/page.tsx' public/image_assets/logo.svg test/api/health.test.ts; do
  [[ -f "$tgt/$p" ]] || missing+=" $p"
done
check "" "$missing" "copy_keeps_dotfiles[nextjs]: dotfiles and nested files arrived"
check 1 "$([[ -x "$tgt/docker-entrypoint.sh" && "$(modeof "$tgt/docker-entrypoint.sh")" == 755 ]] && echo 1 || echo 0)" "template_sh_executable[nextjs]: docker-entrypoint.sh keeps its exec bit"
stray=""
for p in template template-agents template.manifest nextjs ci; do [[ -e "$tgt/$p" ]] && stray+=" $p"; done
check "" "$stray" "copy_keeps_dotfiles[nextjs]: no stray directory or manifest in the target"
check "$N_STACK" "$(count_files "$tgt")" "copy_keeps_dotfiles[nextjs]: exactly the template tree was written"
check 1 "$([[ ! -e "$tgt/AGENTS.md" ]] && echo 1 || echo 0)" "copy_keeps_dotfiles[nextjs]: AGENTS.md waits for the second copy"
out=$(run_agents "$tgt"); ec=$?
check 0 "$ec" "copy_keeps_dotfiles[nextjs]: agents copy exits 0 ($out)"
check "$((N_STACK + 1))" "$(count_files "$tgt")" "copy_keeps_dotfiles[nextjs]: the agents copy wrote one file"
check 1 "$([[ -f "$tgt/AGENTS.md" ]] && cmp -s "$tgt/AGENTS.md" "$NX/template-agents/AGENTS.md" && echo 1 || echo 0)" "copy_keeps_dotfiles[nextjs]: AGENTS.md is the template byte for byte"
# the stack copy composes with the kit copy: no path is written twice
tgt="$T/nx-both"; mkdir -p "$tgt"
out=$(run_stack "$tgt"); ec=$?; out2=$(run_step0 "$tgt" ts); ec2=$?; out3=$(run_ci "$tgt" ts github); ec3=$?
check 000 "$ec$ec2$ec3" "copy_keeps_dotfiles[nextjs]: stack copy, Step 0 and the CI copy all exit 0 ($out $out2 $out3)"
tgt="$T/nx-both2"; mkdir -p "$tgt"
out=$(run_step0 "$tgt" ts); ec=$?; out2=$(run_stack "$tgt"); ec2=$?
check 00 "$ec$ec2" "copy_keeps_dotfiles[nextjs]: Step 0 then the stack copy exit 0 ($out $out2)"

# ── the stack copy refuses and writes nothing ────────────────────────────────
tgt="$T/nx-refuse"; mkdir -p "$tgt"; printf 'mine\n' > "$tgt/package.json"; mkdir -p "$tgt/src/app"; printf 'mine\n' > "$tgt/src/app/layout.tsx"
before=$(snap "$tgt")
out=$(run_stack "$tgt"); ec=$?
check 1 "$([[ $ec -ne 0 && "$out" == *"package.json"* && "$out" == *"src/app/layout.tsx"* && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "stack_copy_refuses_existing_file: nonzero, names every clashing path, ends with the stop line ($out)"
check mine "$(cat "$tgt/package.json")" "stack_copy_refuses_existing_file: existing file untouched"
check "$before" "$(snap "$tgt")" "stack_copy_refuses_existing_file: nothing written"
# a <name>.tmpl source is checked under its project name: a file or a symlink there is a clash, and is never overwritten
tgt="$T/nx-tmpl-clash"; mkdir -p "$tgt/.claude/skills/next-verify"; printf 'mine\n' > "$tgt/.claude/skills/next-verify/SKILL.md"
before=$(snap "$tgt")
out=$(run_stack "$tgt"); ec=$?
check 1 "$([[ $ec -ne 0 && "$out" == *".claude/skills/next-verify/SKILL.md (exists)"* && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "stack_copy_refuses_existing_tmpl_target: nonzero and names SKILL.md (exists) ($out)"
check mine "$(cat "$tgt/.claude/skills/next-verify/SKILL.md")" "stack_copy_refuses_existing_tmpl_target: the user's SKILL.md is untouched"
check "$before" "$(snap "$tgt")" "stack_copy_refuses_existing_tmpl_target: nothing written"
tgt="$T/nx-tmpl-link"; mkdir -p "$tgt/.claude/skills/next-verify"; printf 'mine\n' > "$T/nx-tmpl-link-real.md"
ln -s "$T/nx-tmpl-link-real.md" "$tgt/.claude/skills/next-verify/SKILL.md"
before=$(snap "$tgt")
out=$(run_stack "$tgt"); ec=$?
check 1 "$([[ $ec -ne 0 && "$out" == *".claude/skills/next-verify/SKILL.md (exists)"* && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "stack_copy_refuses_symlinked_tmpl_target: nonzero and names SKILL.md (exists) ($out)"
check "mine|L" "$(cat "$T/nx-tmpl-link-real.md")|$([[ -L "$tgt/.claude/skills/next-verify/SKILL.md" ]] && echo L)" "stack_copy_refuses_symlinked_tmpl_target: the link and its target are untouched"
check "$before" "$(snap "$tgt")" "stack_copy_refuses_symlinked_tmpl_target: nothing written"
tgt="$T/nx-refuse-agents"; mkdir -p "$tgt"; printf 'mine\n' > "$tgt/AGENTS.md"
out=$(run_agents "$tgt"); ec=$?
check 1 "$([[ $ec -ne 0 && "$out" == *"AGENTS.md"* && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "agents_copy_refuses_existing_file: nonzero and names AGENTS.md ($out)"
check mine "$(cat "$tgt/AGENTS.md")" "agents_copy_refuses_existing_file: existing AGENTS.md untouched"
# a user's own files in other places do not block the copy
tgt="$T/nx-own"; mkdir -p "$tgt/src/app" "$tgt/docs"; printf 'mine\n' > "$tgt/README.md"; printf 'mine\n' > "$tgt/src/app/own.tsx"
out=$(run_stack "$tgt"); check 0 "$?" "stack_copy_allows_existing_directory_with_other_files ($out)"
check mine "$(cat "$tgt/src/app/own.tsx")" "stack_copy_allows_existing_directory_with_other_files: own file kept"
# symlinked parents, at the top and nested
mkdir -p "$T/nx-l1" "$T/nx-l1-real"; ln -s "$T/nx-l1-real" "$T/nx-l1/src"
refuses_nx stack_copy_refuses_symlink_parent "$SK" "$STACK_SNIPPET" "$T/nx-l1"
check . "$(snap "$T/nx-l1-real")" "stack_copy_refuses_symlink_parent: nothing written through the link"
mkdir -p "$T/nx-l2/src" "$T/nx-l2-real"; ln -s "$T/nx-l2-real" "$T/nx-l2/src/app"
refuses_nx stack_copy_refuses_nested_symlink_parent "$SK" "$STACK_SNIPPET" "$T/nx-l2"
check . "$(snap "$T/nx-l2-real")" "stack_copy_refuses_nested_symlink_parent: nothing written through the link"
mkdir -p "$T/nx-l3" "$T/nx-l3-real"; ln -s "$T/nx-l3-real" "$T/nx-l3/public"
refuses_nx stack_copy_refuses_symlinked_public "$SK" "$STACK_SNIPPET" "$T/nx-l3"
mkdir -p "$T/nx-l4"; printf 'mine\n' > "$T/nx-l4/src"; before=$(snap "$T/nx-l4")
refuses_raw stack_copy_refuses_file_where_a_directory_is_needed "$(render_sc "$STACK_SNIPPET" "$T/nx-l4" nextjs "")" "not a directory"
check "$before" "$(snap "$T/nx-l4")" "stack_copy_refuses_file_where_a_directory_is_needed: only the user's file is there"
# unwritable and unsearchable directories, caught before the first write
if [[ "$(id -u)" != 0 ]]; then
  tgt="$T/nx-ro"; mkdir -p "$tgt/src/lib"; chmod 0555 "$tgt/src/lib"
  before=$(snap "$tgt")
  refuses_raw stack_copy_refuses_unwritable_dir "$(render_sc "$STACK_SNIPPET" "$tgt" nextjs "")" "not writable"
  check "$before" "$(snap "$tgt")" "stack_copy_refuses_unwritable_dir: zero files written"
  chmod u+w "$tgt/src/lib"
  tgt="$T/nx-ro-root"; mkdir -p "$tgt"; chmod a-w "$tgt"
  refuses_raw stack_copy_refuses_unwritable_root "$(render_sc "$STACK_SNIPPET" "$tgt" nextjs "")" "not writable"
  chmod u+w "$tgt"
  tgt="$T/nx-nosearch"; mkdir -p "$tgt/test"; chmod 0600 "$tgt/test"
  before=$(snap "$tgt")
  refuses_raw stack_copy_refuses_unsearchable_dir "$(render_sc "$STACK_SNIPPET" "$tgt" nextjs "")" "not writable"
  chmod 0755 "$tgt/test"
  check "$before" "$(snap "$tgt")" "stack_copy_refuses_unsearchable_dir: zero files written"
  sk=$(alt_nx unreadable); chmod 000 "$sk/nextjs/template/tsconfig.json"; mkdir -p "$T/nx-unr"
  saved=$SK; SK=$sk
  refuses_raw stack_copy_refuses_unreadable_source "$(render_sc "$STACK_SNIPPET" "$T/nx-unr" nextjs "")" "unreadable"
  SK=$saved
  check . "$(snap "$T/nx-unr")" "stack_copy_refuses_unreadable_source: zero files written"
  chmod 644 "$sk/nextjs/template/tsconfig.json"
fi
# manifest and tree problems
sk=$(alt_nx empty-manifest); : > "$sk/nextjs/template.manifest"; mkdir -p "$T/nx-m1"
refuses_nx stack_copy_refuses_empty_manifest "$sk" "$STACK_SNIPPET" "$T/nx-m1"
saved=$SK; SK=$sk; refuses_raw stack_copy_empty_manifest_message "$(render_sc "$STACK_SNIPPET" "$T/nx-m1" nextjs "")" "missing or empty"; SK=$saved
sk=$(alt_nx no-manifest); rm "$sk/nextjs/template.manifest"; mkdir -p "$T/nx-m2"
refuses_nx stack_copy_refuses_missing_manifest "$sk" "$STACK_SNIPPET" "$T/nx-m2"
sk=$(alt_nx unlisted); printf 'x\n' > "$sk/nextjs/template/zz-unlisted.txt"; mkdir -p "$T/nx-m3"
refuses_nx stack_copy_refuses_file_missing_from_manifest "$sk" "$STACK_SNIPPET" "$T/nx-m3"
sk=$(alt_nx ghost); printf 'template/zz-ghost.txt 644 - -\n' >> "$sk/nextjs/template.manifest"; mkdir -p "$T/nx-m4"
refuses_nx stack_copy_refuses_manifest_line_without_file "$sk" "$STACK_SNIPPET" "$T/nx-m4"
sk=$(alt_nx treelink); ln -s /etc/hosts "$sk/nextjs/template/zz-link"; mkdir -p "$T/nx-m5"
refuses_nx stack_copy_refuses_tree_with_symlink "$sk" "$STACK_SNIPPET" "$T/nx-m5"
sk=$(alt_nx treeempty); mkdir -p "$sk/nextjs/template/zz-empty"; mkdir -p "$T/nx-m6"
refuses_nx stack_copy_refuses_tree_with_empty_dir "$sk" "$STACK_SNIPPET" "$T/nx-m6"
sk=$(alt_nx notree); rm -rf "$sk/nextjs/template"; mkdir -p "$T/nx-m7"
refuses_nx stack_copy_refuses_missing_tree "$sk" "$STACK_SNIPPET" "$T/nx-m7"
sk=$(alt_nx noagents); rm -rf "$sk/nextjs/template-agents"; mkdir -p "$T/nx-m8"
refuses_nx agents_copy_refuses_missing_tree "$sk" "$AGENTS_SNIPPET" "$T/nx-m8"
sk=$(alt_nx dsstore); printf 'x\n' > "$sk/nextjs/template/.DS_Store"; mkdir -p "$T/nx-m9"
saved=$SK; SK=$sk; out=$(bash -c "$(render_sc "$STACK_SNIPPET" "$T/nx-m9" nextjs "")" 2>&1); SK=$saved
check 1 "$([[ "$out" == *".DS_Store"* ]] && echo 1 || echo 0)" "stack_copy_mismatch_refusal_names_the_file ($out)"
# the manifest rows of the other tree do not leak into this copy: the agents copy writes AGENTS.md only
tgt="$T/nx-only-agents"; mkdir -p "$tgt"; run_agents "$tgt" >/dev/null
check "AGENTS.md" "$(cd "$tgt" && find . -type f | sed 's|^\./||')" "agents_copy_writes_only_AGENTS_md"
# the guard values: STACK, CI, PART
mkdir -p "$T/nx-v1" "$T/nx-v2" "$T/nx-v3" "$T/nx-v4" "$T/nx-v5" "$T/nx-v6"
refuses_raw stack_unknown_stack_refused "$(render_sc "$STACK_SNIPPET" "$T/nx-v1" rails "")" "unknown STACK"
refuses_raw stack_empty_stack_refused "$(render_sc "$STACK_SNIPPET" "$T/nx-v2" "" "")" "unknown STACK"
refuses_raw stack_ci_must_stay_empty "$(render_sc "$STACK_SNIPPET" "$T/nx-v3" nextjs github)" "CI must stay empty"
refuses_raw agents_ci_must_stay_empty "$(render_sc "$AGENTS_SNIPPET" "$T/nx-v4" nextjs azure)" "CI must stay empty"
refuses_raw stack_unknown_part_refused "$(render_sc "$STACK_SNIPPET" "$T/nx-v5" nextjs "" weird)" "unknown PART"
sk=$(alt_nx notshared); mkdir -p "$sk/other"
saved=$SK; SK=$sk
refuses_raw stack_skill_dir_must_end_in_shared "$(render_sc "$STACK_SNIPPET" "$T/nx-v6" nextjs "" | python3 -c 'import sys; print(sys.stdin.read().replace(sys.argv[1] + "/shared", sys.argv[1] + "/other"))' "$sk")" "must end in /shared"
SK=$saved
check ". . . . . ." "$(snap "$T/nx-v1") $(snap "$T/nx-v2") $(snap "$T/nx-v3") $(snap "$T/nx-v4") $(snap "$T/nx-v5") $(snap "$T/nx-v6")" "stack_guard_value_refusals: nothing copied"
refuses_raw stack_empty_target_refused "$(render_sc "$STACK_SNIPPET" "" nextjs "")" "target"
refuses_raw stack_unsubstituted_target_refused "$(printf '%s\n' "$STACK_SNIPPET" | python3 -c 'import sys; print(sys.stdin.read().replace("<skill-dir>", sys.argv[1]))' "$SK")" "not substituted"
refuses_raw stack_unsubstituted_skill_dir_refused "$(printf '%s\n' "$STACK_SNIPPET" | python3 -c 'import sys; print(sys.stdin.read().replace("<target>", sys.argv[1]))' "$T/h")" "not substituted"
refuses_raw stack_missing_target_refused "$(render_sc "$STACK_SNIPPET" "$T/no/such/dir" nextjs "")" "existing directory"
# hostile names for the target and the skill dir, through both stack fences
run="$T/runnx"; mkdir -p "$run"
for fence in stack agents; do
  snip=$STACK_SNIPPET; want=$N_STACK; [[ $fence == agents ]] && { snip=$AGENTS_SNIPPET; want=$N_AGENTS; }
  for kind in TGT SK; do
    for name in "${HOSTILE[@]}"; do
      rm -rf "$T/hmx"; mkdir -p "$T/hmx"
      if [[ $kind == TGT ]]; then
        tgt="$T/hmx/$name"; mkdir -p "$tgt"; sk=$SK
      else
        sk="$T/hmx/$name"; mkdir -p "$sk/shared"; cp -Rp "$NX" "$sk/nextjs"; tgt="$T/hmx-tgt"; rm -rf "$tgt"; mkdir -p "$tgt"
      fi
      saved=$SK; SK=$sk
      out=$(cd "$run" && bash -c "$(render_sc "$snip" "$tgt" nextjs "")" 2>&1); ec=$?
      SK=$saved
      got=$(count_files "$tgt")
      label="hostile_${kind}[nextjs/$fence/$(printf '%q' "$name")]"
      if [[ "$name" == *$'\n'* ]]; then
        check 1 "$([[ $ec -ne 0 && "$(snap "$tgt")" == . ]] && echo 1 || echo 0)" "$label: refused with nothing written"
      else
        check 1 "$([[ $ec -eq 0 && $got == "$want" ]] && echo 1 || echo 0)" "$label: copied $want files (exit $ec, got $got: $out)"
      fi
      check 0 "$([[ -e "$run/PWN" || -e "$T/PWN" || -e "$tgt/PWN" ]] && echo 1 || echo 0)" "$label: no command ran"
    done
  done
done
# relative targets: a dash and a literal tilde
for name in '-dash' '~'; do
  rm -rf "$run"; mkdir -p "$run/$name"
  out=$(cd "$run" && bash -c "$(render_sc "$STACK_SNIPPET" "$name" nextjs "")" 2>&1); ec=$?
  check 1 "$([[ $ec -eq 0 && -f "$run/$name/package.json" ]] && echo 1 || echo 0)" "hostile_relative_target[nextjs/$name]: copied ($out)"
done
# an unsubstituted guard and a read-only plugin cache
sk=$(alt_nx rocache); chmod -R a-w "$sk/nextjs"; tgt="$T/nx-rocache"; mkdir -p "$tgt"
saved=$SK; SK=$sk; out=$(run_stack "$tgt"); ec=$?; SK=$saved
check 0 "$ec" "stack_copy_from_read_only_cache_exits_0 ($out)"
check 1 "$([[ -w "$tgt/src" && -w "$tgt/src/app" && -w "$tgt/package.json" ]] && echo 1 || echo 0)" "stack_copy_from_read_only_cache_leaves_writable_paths"
check "" "$(cd "$tgt" && find . -type f -name '*.sh' ! -perm -u+x)" "stack_copy_from_read_only_cache_keeps_exec_bits"
chmod -R u+w "$sk/nextjs"
# the project root and existing directories keep their modes
for m in 0700 2775 0750; do
  tgt="$T/nx-mode-$m"; mkdir -p "$tgt/src" "$tgt/test"; chmod "$m" "$tgt" "$tgt/src"
  before=$(modeof "$tgt"); beforec=$(modeof "$tgt/src")
  run_stack "$tgt" >/dev/null
  check "$before" "$(modeof "$tgt")" "stack_root_mode_kept[$m]: the project root mode is unchanged"
  check "$beforec" "$(modeof "$tgt/src")" "stack_root_mode_kept[$m]: an existing src keeps its mode"
done
# every copied file gets the manifest mode
tgt="$T/nx-modes"; mkdir -p "$tgt"; run_stack "$tgt" >/dev/null; run_agents "$tgt" >/dev/null
bad=""
while read -r p m _; do
  case "$p" in template/*) f=${p#template/} ;; template-agents/*) f=${p#template-agents/} ;; *) continue ;; esac
  f=${f%.tmpl}
  [[ "$(modeof "$tgt/$f")" == "$m" ]] || bad+=" $f"
done < <(grep -v '^#' "$NX/template.manifest")
check "" "$bad" "stack_copy_yields_manifest_modes"
# cp and chmod failures after the pre-checks report the state
for which in cp chmod; do
  tgt="$T/nx-stub-$which"; mkdir -p "$tgt"; rm -f "$T/stub-count"
  out=$(PATH="$T/stubs:$PATH" STUB_COUNT="$T/stub-count" STUB_FAIL_AT=3 bash -c "$(render_sc "$STACK_SNIPPET" "$tgt" nextjs "")" 2>&1); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out" == *"$STOPLINE"* && "$out" == *"Files already written:"* ]] && echo 1 || echo 0)" "stack_${which}_failure_reports_state: nonzero, lists the written files, ends with the stop line ($out)"
done
# the fences behave the same under zsh, and a refusal never kills the caller's shell
if command -v zsh >/dev/null 2>&1; then
  tgt="$T/nx-z1"; mkdir -p "$tgt"
  out=$(zsh -c "$(render_sc "$STACK_SNIPPET" "$tgt" nextjs "")" 2>&1); ec=$?
  check 0 "$ec" "zsh_stack_success_exits_0 ($out)"
  check "$N_STACK" "$(count_files "$tgt")" "zsh_stack_success_copies"
  out=$(zsh -c "$(render_sc "$AGENTS_SNIPPET" "$tgt" nextjs "")" 2>&1); ec=$?
  check 0 "$ec" "zsh_agents_success_exits_0 ($out)"
  before=$(snap "$tgt")
  out=$(zsh -c "$(render_sc "$STACK_SNIPPET" "$tgt" nextjs "")
echo CALLER_SURVIVED" 2>&1)
  check 1 "$([[ "$out" == *CALLER_SURVIVED* && "$out" == *Refusing* ]] && echo 1 || echo 0)" "zsh_stack_refusal_leaves_caller_shell_alive"
  check "$before" "$(snap "$tgt")" "zsh_stack_refusal_copies_nothing"
fi
# ── validate-scaffold-configs.sh checks the stack template files ─────────────
# vsc <shell snippet run in the scratch repo before the check> — echoes the check's output, then its exit code.
vsc() {
  local w="$T/vsc" out ec
  rm -rf "$w"; mkdir -p "$w/scripts" "$w/skills"
  cp "$REPO_ROOT/scripts/validate-scaffold-configs.sh" "$w/scripts/"; cp -R "$SK" "$w/skills/scaffold"
  (cd "$w" && eval "$1")
  out=$(cd "$w" && bash scripts/validate-scaffold-configs.sh 2>&1); ec=$?
  printf '%s\nEXIT=%s\n' "$out" "$ec"
}
if command -v jq >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  out=$(vsc ':')
  check 1 "$([[ "$out" == *"ok    skills/scaffold/nextjs/template/package.json"* && "$out" == *"ok    skills/scaffold/nextjs/template/eslint.config.mjs"* && "$out" == *"EXIT=0" ]] && echo 1 || echo 0)" "validate_configs_checks_template_files: json and mjs files are validated ($out)"
  check 1 "$([[ "$out" != *"FAIL  skills/scaffold/shared"* && "$out" == *"EXIT=0" ]] && echo 1 || echo 0)" "validate_configs_shared_manifest_does_not_trip_the_stack_check: the shared manifest has no JSON or JS by design ($out)"
  out=$(vsc "printf '{' >> skills/scaffold/nextjs/template/package.json")
  check 1 "$([[ "$out" == *"FAIL  skills/scaffold/nextjs/template/package.json"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_on_invalid_template_json ($out)"
  out=$(vsc "printf 'const = ;\\n' >> skills/scaffold/nextjs/template/eslint.config.mjs")
  check 1 "$([[ "$out" == *"FAIL  skills/scaffold/nextjs/template/eslint.config.mjs"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_on_invalid_template_mjs ($out)"
  out=$(vsc "printf 'const = ;\\n' > skills/scaffold/nextjs/template/zz.cjs")
  check 1 "$([[ "$out" == *"FAIL  skills/scaffold/nextjs/template/zz.cjs"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_on_invalid_template_cjs ($out)"
  out=$(vsc "mv skills/scaffold/nextjs/template skills/scaffold/nextjs/template-moved")
  check 1 "$([[ "$out" == *"template.manifest exists but template/ holds no JSON or JS file"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_when_anchor_deleted: a renamed template/ tree fails while its manifest exists ($out)"
  out=$(vsc "find skills/scaffold/nextjs/template \\( -name '*.json' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \\) -delete")
  check 1 "$([[ "$out" == *"template.manifest exists but template/ holds no JSON or JS file"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_on_empty_match: a template/ tree with no JSON or JS file ($out)"
  out=$(vsc "printf '{' >> skills/scaffold/shared/template-settings-ts/.claude/settings.json")
  check 1 "$([[ "$out" == *"FAIL  skills/scaffold/shared/template-settings-ts/.claude/settings.json"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_on_invalid_settings_json ($out)"
  out=$(vsc "rm -rf skills/scaffold/shared/template-settings-py")
  check 1 "$([[ "$out" == *"template-settings-py  — no settings.json to validate"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_on_empty_match: a missing settings tree ($out)"
  out=$(vsc "rm -rf skills/scaffold/shared/template-settings-ts skills/scaffold/shared/template-settings-py")
  check 1 "$([[ "$out" == *"template-settings-ts  — no settings.json to validate"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_when_anchor_deleted: both settings trees gone ($out)"
  out=$(vsc "rm -rf skills/scaffold/*/template skills/scaffold/*/template.manifest skills/scaffold/shared/template-settings-*; rm -f skills/scaffold/*/config-files.md")
  check 1 "$([[ "$out" == *"nothing was validated"* && "$out" == *"EXIT=1" ]] && echo 1 || echo 0)" "validate_configs_fails_when_nothing_is_validated ($out)"
elif [[ "${CI:-}" == true ]]; then
  FAIL=$((FAIL + 1)); echo "FAIL: jq or node is missing but CI=true; the validate-scaffold-configs tests must run in CI"
else
  echo "SKIP: validate-scaffold-configs tests (jq or node not installed)"
fi

# ── PART=settings, PART=late, PART=claude and the AGENTS.md tail ─────────────
for sv in nextjs:ts fastapi:py; do
  st=${sv%%:*}; v=${sv##*:}
  tgt="$T/part-$st"; mkdir -p "$tgt"
  out=$(run_part "$tgt" "$st" base)
  out2=$(run_part "$tgt" "$st" settings); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out2" == *"AGENTS.md does not exist yet"* && ! -e "$tgt/.claude/settings.json" ]] && echo 1 || echo 0)" "part_settings[$st]: refused before AGENTS.md exists ($out2)"
  out3=$(run_part "$tgt" "$st" late); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out3" == *"AGENTS.md does not exist yet"* && ! -e "$tgt/FUTURE.md" ]] && echo 1 || echo 0)" "part_late[$st]: refused before AGENTS.md exists ($out3)"
  printf '# AGENTS.md\n' > "$tgt/AGENTS.md"
  out2=$(run_part "$tgt" "$st" settings); ec=$?
  check 0 "$ec" "part_settings[$st]: exits 0 ($out2)"
  check 1 "$([[ -f "$tgt/.claude/settings.json" ]] && cmp -s "$tgt/.claude/settings.json" "$SHARED/template-settings-$v/.claude/settings.json" && echo 1 || echo 0)" "part_settings[$st]: settings.json is the $v variant byte for byte"
  want=$(grep -F '  .claude/settings.json' "$REPO_ROOT/tests/golden/$st-github.sha256" | cut -d' ' -f1)
  check "$want" "$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$tgt/.claude/settings.json")" "part_settings[$st]: settings.json matches the golden"
  out3=$(run_part "$tgt" "$st" late); ec=$?
  check 0 "$ec" "part_late[$st]: exits 0 ($out3)"
  missing=""
  for p in FUTURE.md docs/CONSTITUTION.md .claude/skills/skill-audit/SKILL.md; do [[ -f "$tgt/$p" ]] || missing+=" $p"; done
  check "" "$missing" "part_late[$st]: the three late files arrived"
  check 1 "$([[ "$(grep -c '__TC_PROJECT_TITLE__' "$tgt/docs/CONSTITUTION.md")" == 1 ]] && echo 1 || echo 0)" "part_late[$st]: CONSTITUTION carries its one placeholder"
  check 1 "$([[ ! -e "$tgt/AGENTS-tail.md" && ! -e "$tgt/template-tail" && ! -e "$tgt/.claude/AGENTS-tail.md" ]] && echo 1 || echo 0)" "part_late[$st]: the tail is never copied as a file"
  out=$(run_part "$tgt" "$st" late); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "part_late[$st]: a second run refuses (the files exist)"
  out=$(run_part "$tgt" "$st" settings); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "part_settings[$st]: a second run refuses (settings.json exists)"
done
# settings and late refuse without Step 0, and with a STACK that does not match it
for part in settings late; do
  tgt="$T/part-nostep0-$part"; mkdir -p "$tgt"; printf '# AGENTS.md\n' > "$tgt/AGENTS.md"
  refuses_raw "part_${part}_refuses_without_step0" "$(render_sc "$STEP0" "$tgt" nextjs "" "$part")" "does not match"
  check "$(printf '.\n./AGENTS.md')" "$(snap "$tgt")" "part_${part}_refuses_without_step0: nothing written but the AGENTS.md the test placed"
  tgt="$T/part-mismatch-$part"; mkdir -p "$tgt"; run_part "$tgt" nextjs base >/dev/null; printf '# AGENTS.md\n' > "$tgt/AGENTS.md"
  before=$(snap "$tgt")
  refuses_raw "part_${part}_refuses_a_stack_that_differs_from_step0" "$(render_sc "$STEP0" "$tgt" fastapi "" "$part")" "does not match"
  check "$before" "$(snap "$tgt")" "part_${part}_refuses_a_stack_that_differs_from_step0: nothing written"
  refuses_raw "part_${part}_ci_must_stay_empty" "$(render_sc "$STEP0" "$T/part-nostep0-$part" nextjs github "$part")" "CI must stay empty"
done
# an existing settings.json is never overwritten
tgt="$T/part-own-settings"; mkdir -p "$tgt/.claude"; printf 'mine\n' > "$tgt/.claude/settings.json"; run_part "$tgt" nextjs base >/dev/null; printf '# AGENTS.md\n' > "$tgt/AGENTS.md"
out=$(run_part "$tgt" nextjs settings); ec=$?
check 1 "$([[ $ec -ne 0 && "$out" == *".claude/settings.json"* ]] && echo 1 || echo 0)" "part_settings_refuses_existing_file: names settings.json ($out)"
check mine "$(cat "$tgt/.claude/settings.json")" "part_settings_refuses_existing_file: the user's file is untouched"
# the AGENTS.md tail: one marker, fixed per-stack values, atomic append, and the migrate path
TAIL_FILE="$SHARED/template-tail/AGENTS-tail.md"
check 1 "$(grep -c 'see delta table for stack command' "$TAIL_FILE")" "agents_tail: the tail file holds the marker exactly once"
TAIL_CMD=$(snippet "$SHARED/harness-kit-finalize.md" '^## Step G\b' 1)
check 1 "$([[ "$TAIL_CMD" == *'ENVIRON["TC"]'* && "$TAIL_CMD" != *'sed '* ]] && echo 1 || echo 0)" "agents_tail: the command fills the marker from fixed values, with no sed pattern"
run_tail() { # run_tail <stack> <project dir> [skill-dir text for the tail path] — the documented command in <project dir>
  local body
  body=$(printf '%s\n' "$TAIL_CMD" | python3 -c 'import sys
t = sys.stdin.read().replace("STACK=\n", "STACK=" + sys.argv[1] + "\n", 1)
t = t.replace("<skill-dir>/shared/template-tail", sys.argv[3] + "/template-tail" if len(sys.argv) > 3 else "<skill-dir>/shared/template-tail")
print(t.replace("<skill-dir>", sys.argv[2]))' "$1" "$SK" ${3:+"$3"})
  (cd "$2" && bash -c "$body" 2>&1)
}
for sc in nextjs:'pnpm exec tsc --noEmit --incremental' vite-react:'pnpm exec tsc --noEmit --incremental' nestjs:'pnpm exec tsc --noEmit --incremental' fastapi:'python -m pyright src/'; do
  st=${sc%%:*}; cmd=${sc#*:}
  tgt="$T/tail-$st"; rm -rf "$tgt"; mkdir -p "$tgt"; cp "$NX/template-agents/AGENTS.md" "$tgt/AGENTS.md"; before=$(cat "$tgt/AGENTS.md")
  out=$(run_tail "$st" "$tgt"); ec=$?
  check 0 "$ec" "agents_tail[$st]: the documented command exits 0 ($out)"
  check 1 "$([[ "$(grep -c '^## AI Harness$' "$tgt/AGENTS.md")" == 1 && "$(grep -c 'see delta table for stack command' "$tgt/AGENTS.md")" == 0 && "$(grep -cF "incremental type-check ($cmd)" "$tgt/AGENTS.md")" == 1 ]] && echo 1 || echo 0)" "agents_tail[$st]: one tail, with the fixed command inside the parentheses"
  check ok "$(python3 - "$NX/template-agents/AGENTS.md" "$TAIL_FILE" "$cmd" "$tgt/AGENTS.md" <<'PY'
import sys
base, tail, cmd, got = sys.argv[1:]
body = open(tail, "rb").read().replace(b"see delta table for stack command", cmd.encode())
want = open(base, "rb").read() + b"\n" + body.rstrip(b"\n") + b"\n"
print("ok" if open(got, "rb").read() == want else "differs")
PY
)" "agents_tail[$st]: the appended bytes are one blank line, then the tail with the marker filled"
  check 1 "$([[ "$(head -c "${#before}" "$tgt/AGENTS.md")" == "$before" ]] && echo 1 || echo 0)" "agents_tail[$st]: the stack's AGENTS.md body is untouched"
done
# an unknown or empty STACK appends nothing
for bad in rails ''; do
  tgt="$T/tail-bad"; rm -rf "$tgt"; mkdir -p "$tgt"; printf 'body\n' > "$tgt/AGENTS.md"
  out=$(run_tail "$bad" "$tgt"); ec=$?
  check 1 "$([[ $ec -ne 0 && "$(cat "$tgt/AGENTS.md")" == body ]] && echo 1 || echo 0)" "agents_tail_refuses_stack[$bad]: nonzero, AGENTS.md untouched ($out)"
done
tgt="$T/tail-nofile"; rm -rf "$tgt"; mkdir -p "$tgt"; printf 'body\n' > "$tgt/AGENTS.md"
out=$(cd "$tgt" && bash -c "$(printf '%s\n' "$TAIL_CMD" | python3 -c 'import sys; print(sys.stdin.read().replace("STACK=\n", "STACK=nextjs\n", 1).replace("<skill-dir>", sys.argv[1]))' "$T/no-such-skill")" 2>&1); ec=$?
check 1 "$([[ $ec -ne 0 && "$(cat "$tgt/AGENTS.md")" == body ]] && echo 1 || echo 0)" "agents_tail_is_atomic: a failed read appends nothing, not even the blank line ($out)"
# without an AGENTS.md the command refuses and creates nothing, so >> cannot make the file
tgt="$T/tail-noagents"; rm -rf "$tgt"; mkdir -p "$tgt"; before=$(snap "$tgt")
out=$(run_tail nextjs "$tgt"); ec=$?
check 1 "$([[ $ec -ne 0 && "$out" == *"AGENTS.md does not exist"* ]] && echo 1 || echo 0)" "agents_tail_refuses_without_agents_md: nonzero and says so ($out)"
check "$before" "$(snap "$tgt")" "agents_tail_refuses_without_agents_md: no AGENTS.md was created"
# the tail command behaves the same under zsh, and a refusal never kills the caller's shell
if command -v zsh >/dev/null 2>&1; then
  zsh_tail() { # zsh_tail <stack> <project dir> — the documented command under zsh, then a marker line
    local body
    body=$(printf '%s\n' "$TAIL_CMD" | python3 -c 'import sys
print(sys.stdin.read().replace("STACK=\n", "STACK=" + sys.argv[1] + "\n", 1).replace("<skill-dir>", sys.argv[2]))' "$1" "$SK")
    (cd "$2" && zsh -c "$body
echo CALLER_SURVIVED" 2>&1)
  }
  tgt="$T/tail-zsh"; rm -rf "$tgt"; mkdir -p "$tgt"; printf 'body\n' > "$tgt/AGENTS.md"
  out=$(zsh_tail nextjs "$tgt")
  check 1 "$([[ "$out" == *CALLER_SURVIVED* && "$(grep -c '^## AI Harness$' "$tgt/AGENTS.md")" == 1 ]] && echo 1 || echo 0)" "zsh_agents_tail_success: appends and returns ($out)"
  tgt="$T/tail-zsh-bad"; rm -rf "$tgt"; mkdir -p "$tgt"; printf 'body\n' > "$tgt/AGENTS.md"
  out=$(zsh_tail rails "$tgt")
  check 1 "$([[ "$out" == *CALLER_SURVIVED* && "$out" == *Refusing* && "$(cat "$tgt/AGENTS.md")" == body ]] && echo 1 || echo 0)" "zsh_agents_tail_refusal_leaves_caller_shell_alive: unknown STACK ($out)"
  tgt="$T/tail-zsh-none"; rm -rf "$tgt"; mkdir -p "$tgt"; before=$(snap "$tgt")
  out=$(zsh_tail nextjs "$tgt")
  check 1 "$([[ "$out" == *CALLER_SURVIVED* && "$out" == *"AGENTS.md does not exist"* ]] && echo 1 || echo 0)" "zsh_agents_tail_refusal_leaves_caller_shell_alive: no AGENTS.md ($out)"
  check "$before" "$(snap "$tgt")" "zsh_agents_tail_refusal: no AGENTS.md was created"
elif [[ "${CI:-}" == true ]]; then
  FAIL=$((FAIL + 1)); echo "FAIL: zsh is not installed but CI=true; the zsh tail tests must run in CI"
else
  echo "SKIP: zsh tail tests (zsh not installed)"
fi
# migrate reads the tail from <skill-dir>/../scaffold/shared/..., with <skill-dir> the migrate directory
tgt="$T/tail-migrate"; rm -rf "$tgt"; mkdir -p "$tgt"; printf 'body\n' > "$tgt/AGENTS.md"
body=$(printf '%s\n' "$TAIL_CMD" | python3 -c 'import sys
t = sys.stdin.read().replace("STACK=\n", "STACK=nextjs\n", 1)
t = t.replace("<skill-dir>/shared/template-tail", "<skill-dir>/../scaffold/shared/template-tail")
print(t.replace("<skill-dir>", sys.argv[1]))' "$REPO_ROOT/skills/migrate")
out=$(cd "$tgt" && bash -c "$body" 2>&1); ec=$?
check 1 "$([[ $ec -eq 0 && "$(grep -c '^## AI Harness$' "$tgt/AGENTS.md")" == 1 ]] && echo 1 || echo 0)" "agents_tail_migrate_path: the path the migrate doc names resolves and appends ($out)"
# the path Step 4f-3 itself names (not another paragraph of the phase) resolves from the migrate directory
step_4f3=$(awk '/^\*\*Step 4f-3[: ]/ { on = 1; next } /^\*\*Step / { on = 0 } on' "$REPO_ROOT/skills/migrate/general/phase-4-upgrade.md")
named=$(grep -o '<skill-dir>/\.\./scaffold/shared/template-tail/AGENTS-tail\.md' <<<"$step_4f3" | head -n 1)
check 1 "$([[ -n "$named" ]] && echo 1 || echo 0)" "agents_tail_migrate_path: Step 4f-3 names the tail path"
check 1 "$([[ -f "$REPO_ROOT/skills/migrate/${named#<skill-dir>/}" ]] && echo 1 || echo 0)" "agents_tail_migrate_path: the path Step 4f-3 names resolves to a file"
# the task-management text appends with a plain command
TM_CMD=$(snippet "$NX/source-files.md" '^### 7b\.' 1)
tgt="$T/tail-tm"; rm -rf "$tgt"; mkdir -p "$tgt"; printf 'body\n' > "$tgt/AGENTS.md"
out=$(cd "$tgt" && bash -c "$(printf '%s\n' "$TM_CMD" | python3 -c 'import sys; print(sys.stdin.read().replace("<skill-dir>", sys.argv[1]))' "$SK")" 2>&1); ec=$?
check 1 "$([[ $ec -eq 0 && "$(grep -c '^## Task Management$' "$tgt/AGENTS.md")" == 1 ]] && echo 1 || echo 0)" "task_management_append: the documented command appends the section ($out)"
# Step D fills the title with the Edit tool: no script and no heredoc carries the name
check 0 "$(grep -c 'TC_NAME' "$SHARED/harness-kit-finalize.md")" "step_d_has_no_name_heredoc"
check 1 "$([[ "$(snippet "$SHARED/harness-kit-finalize.md" '^## Step D\b' 1)" == *"grep -n '__TC_' docs/CONSTITUTION.md"* ]] && echo 1 || echo 0)" "step_d_greps_for_leftover_placeholders"

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
# shellcheck disable=SC2030,SC2031  # the subshell keeps the dist skill dir out of the rest of the run
(SK="$dist/scaffold"; run_step0 "$tgt" ts) >/dev/null 2>&1
check 1 "$([[ -x "$tgt/.claude/hooks/session-context.sh" && -f "$tgt/.gitleaks.toml" ]] && echo 1 || echo 0)" "dist_keeps_templates: copy from the dist layout keeps dotfiles and exec bits"
# the registered skill set (top-level skills/*/SKILL.md) is the same in the dist, and the SKILL.md files
# the templates carry sit deeper, so a loader that reads one level never registers them
src_set=$(cd "$REPO_ROOT/skills" && find . -mindepth 2 -maxdepth 2 -name SKILL.md | LC_ALL=C sort | tr '\n' ' ')
dist_set=$(cd "$dist" && find . -mindepth 2 -maxdepth 2 -name SKILL.md | LC_ALL=C sort | tr '\n' ' ')
check "$src_set" "$dist_set" "dist_registered_skill_set: the top-level skills match the source"
check 1 "$([[ -n "$src_set" ]] && echo 1 || echo 0)" "dist_registered_skill_set: the source has registered skills"
tpl_skills=$(cd "$dist" && find . -name SKILL.md.tmpl -path '*/template*/*' | wc -l | tr -d ' ')
check 1 "$([[ "$tpl_skills" -ge 3 ]] && echo 1 || echo 0)" "dist_registered_skill_set: the template skills are in the dist as SKILL.md.tmpl ($tpl_skills)"
check "" "$(cd "$dist" && find . -name SKILL.md -path '*/template*/*')" "dist_registered_skill_set: no file named SKILL.md sits in a dist template tree"
# the stack trees and their manifest reach the dist too, with dotfiles, modes and bytes
python3 - "$NX" "$dist/scaffold/nextjs" > "$T/dist-nx.diff" <<'PY'
import os, sys
src, dist = sys.argv[1:]
def listing(root):
    out = {}
    for tree in ("template", "template-agents"):
        for dp, _, fs in os.walk(os.path.join(root, tree)):
            for f in fs:
                full = os.path.join(dp, f)
                out[os.path.relpath(full, root)] = (os.stat(full).st_mode & 0o777, open(full, "rb").read())
    return out
a, b = listing(src), (listing(dist) if os.path.isdir(dist) else {})
if not a:
    print("EMPTY source nextjs templates")
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
check "" "$(cat "$T/dist-nx.diff")" "dist_keeps_templates[nextjs]"
tgt="$T/dist-nx-copy"; mkdir -p "$tgt"
(SK="$dist/scaffold"; run_stack "$tgt") >/dev/null 2>&1
check 1 "$([[ -f "$tgt/.gitignore" && -x "$tgt/docker-entrypoint.sh" && "$(count_files "$tgt")" == "$N_STACK" ]] && echo 1 || echo 0)" "dist_keeps_templates[nextjs]: the stack copy from the dist layout keeps dotfiles and exec bits"

echo "test-template-copy: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

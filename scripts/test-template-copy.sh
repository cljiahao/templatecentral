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

# render <snippet-text> <target> <selector> — the older selector spelling, mapped onto STACK and CI:
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
CI_SNIPPET=$(snippet "$SHARED/harness-kit-enforcement.md" '^## Step B3\b' 1) || CI_SNIPPET=""
check 1 "$([[ -n "$STEP0" && -n "$CI_SNIPPET" ]] && echo 1 || echo 0)" "copy instructions found in the kit markdown (Step 0, Step B3 CI)"

stack_of() { [[ "$1" == py ]] && echo fastapi || echo nextjs; }
run_step0() { # run_step0 <target> <variant ts|py>
  bash -c "$(render_sc "$STEP0" "$1" "$(stack_of "$2")" "")" 2>&1
}
run_ci() { # run_ci <target> <variant ts|py> <host github|azure> — Step B3 requires Step 0's lefthook.yml, so run Step 0 first when it is absent
  [[ -f "$1/lefthook.yml" ]] || bash -c "$(render_sc "$STEP0" "$1" "$(stack_of "$2")" "")" >/dev/null 2>&1
  bash -c "$(render_sc "$CI_SNIPPET" "$1" "$(stack_of "$2")" "$3")" 2>&1
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
  zsh -c "$(render "$STEP0" "$tgt" "template template-ts")" >/dev/null 2>&1
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

# the two guards are the same script apart from the SEL and WHAT lines
norm() { printf '%s\n' "$1" | grep -v '^STACK=\|^CI=\|^PART=\|^WHAT=' ; }
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
check 0 "$(find "$T/u1" -type f | wc -l | tr -d ' ')" "unknown_stack_refused: nothing copied"
refuses_raw empty_stack_refused "$(mkdir -p "$T/u2" && render_sc "$STEP0" "$T/u2" "" "")" "unknown STACK"
refuses_raw unknown_ci_refused "$(mkdir -p "$T/u3" && render_sc "$CI_SNIPPET" "$T/u3" "nextjs" "gitlab")" "unknown CI"
refuses_raw empty_ci_in_ci_step_refused "$(mkdir -p "$T/u4" && render_sc "$CI_SNIPPET" "$T/u4" "nextjs" "")" "unknown CI"
check 0 "$(find "$T/u3" "$T/u4" -type f | wc -l | tr -d ' ')" "unknown_ci_refused: nothing copied"

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
  refuses_raw "not_a_directory_refused[$name]" "$(render_sc "$STEP0" "$tgt" nextjs "")" "not a directory"
  check 1 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "not_a_directory_refused[$name]: only the user's file is there"
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

# seed-neither removes the gate script only when it is the template's byte for byte
NEITHER=$(snippet "$SHARED/harness-kit-enforcement.md" '^## Step B3\b' 2) || NEITHER=""
tgt="$T/sn1"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null
printf '# local edit\n' >> "$tgt/.claude/ci-gates.sh"
refuses_raw seed_neither_keeps_a_modified_script "$(render_sc "$NEITHER" "$tgt" nextjs "")" "differs from the template"
check 1 "$(grep -c 'local edit' "$tgt/.claude/ci-gates.sh")" "seed_neither_keeps_a_modified_script: the user's edit survives"
refuses_raw seed_neither_refuses_unsubstituted_target "$(printf '%s\n' "$NEITHER" | python3 -c 'import sys; print(sys.stdin.read().replace("<skill-dir>", sys.argv[1]))' "$SK")" "not substituted"
refuses_raw seed_neither_refuses_missing_dir "$(render_sc "$NEITHER" "$T/no/such" nextjs "")" "existing directory"
tgt="$T/sn2"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null
out=$(bash -c "$(render_sc "$NEITHER" "$tgt" nextjs "")" 2>&1); ec=$?
check 0 "$ec" "seed_neither_removes_an_identical_script ($out)"
check 1 "$([[ ! -e "$tgt/.claude/ci-gates.sh" && -e "$tgt/.claude/verify-harness.sh" ]] && echo 1 || echo 0)" "seed_neither_removes_an_identical_script: only ci-gates.sh is gone"

# the refusal for a manifest/tree mismatch names the offending files
sk=$(alt_skill dsstore); printf 'x\n' > "$sk/shared/template/.DS_Store"; mkdir -p "$T/ds"
saved=$SK; SK=$sk; out=$(bash -c "$(render "$STEP0" "$T/ds" "template template-ts")" 2>&1); SK=$saved
check 1 "$([[ "$out" == *".DS_Store"* ]] && echo 1 || echo 0)" "mismatch_refusal_names_the_file ($out)"

# ── seed-neither symlinks, pre-checks, PART, hostile-name matrix ──────────────
refuses_dir() { # refuses_dir <name> <snippet text> <message substring> <dir that must stay empty of new files>
  refuses_raw "$1" "$2" "$3"
}
# the seed-neither fence follows no symlink
tgt="$T/sl1"; mkdir -p "$tgt" "$T/sl1-real/.claude"; cp "$SHARED/template/.claude/ci-gates.sh" "$T/sl1-real/.claude/ci-gates.sh"
ln -s "$T/sl1-real/.claude" "$tgt/.claude"
refuses_raw seed_neither_refuses_symlinked_claude_dir "$(render_sc "$NEITHER" "$tgt" nextjs "")" "symlink"
check 1 "$([[ -f "$T/sl1-real/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "seed_neither_refuses_symlinked_claude_dir: the link target is untouched"
tgt="$T/sl2"; mkdir -p "$tgt/.claude"; cp "$SHARED/template/.claude/ci-gates.sh" "$T/sl2-real.sh"; ln -s "$T/sl2-real.sh" "$tgt/.claude/ci-gates.sh"
refuses_raw seed_neither_refuses_symlinked_gate "$(render_sc "$NEITHER" "$tgt" nextjs "")" "symlink"
check 1 "$([[ -f "$T/sl2-real.sh" && -L "$tgt/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "seed_neither_refuses_symlinked_gate: the link and its target are untouched"
tgt="$T/sl3"; mkdir -p "$tgt/.claude"; ln -s "$T/does-not-exist" "$tgt/.claude/ci-gates.sh"
refuses_raw seed_neither_refuses_dangling_symlink_gate "$(render_sc "$NEITHER" "$tgt" nextjs "")" "symlink"
check 1 "$([[ -L "$tgt/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "seed_neither_refuses_dangling_symlink_gate: the link is still there"
tgt="$T/sl4"; mkdir -p "$tgt/.claude/ci-gates.sh"
refuses_raw seed_neither_refuses_a_directory_gate "$(render_sc "$NEITHER" "$tgt" nextjs "")" "not a regular file"

# an unwritable existing directory is caught before anything is written
if [[ "$(id -u)" != 0 ]]; then
  tgt="$T/prew"; mkdir -p "$tgt/.lefthook"; chmod 0555 "$tgt/.lefthook"
  refuses_raw prewrite_check_refuses_unwritable_dir "$(render_sc "$STEP0" "$tgt" nextjs "")" "not writable"
  check 0 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "prewrite_check_refuses_unwritable_dir: zero files written"
  chmod u+w "$tgt/.lefthook"
  sk=$(alt_skill unreadable); chmod 000 "$sk/shared/template/.gitleaks.toml"; mkdir -p "$T/prer"
  saved=$SK; SK=$sk
  refuses_raw prewrite_check_refuses_unreadable_source "$(render_sc "$STEP0" "$T/prer" nextjs "")" "unreadable"
  SK=$saved
  check 0 "$(find "$T/prer" -type f | wc -l | tr -d ' ')" "prewrite_check_refuses_unreadable_source: zero files written"
  chmod 644 "$sk/shared/template/.gitleaks.toml"
fi

# PART and CI must agree with the fence they are in
for combo in "STEP0|github|base|CI must stay empty" "STEP0||ci|unknown CI" "CI|github|base|CI must stay empty" "CI||ci|unknown CI" "STEP0||weird|unknown PART" "CI|github|weird|unknown PART"; do
  IFS='|' read -r which ci part msg <<<"$combo"
  snip=$STEP0; [[ $which == CI ]] && snip=$CI_SNIPPET
  tgt="$T/part-$which-$part-$ci"; mkdir -p "$tgt"
  refuses_raw "part_mismatch[$which ci=$ci part=$part]" "$(render_sc "$snip" "$tgt" nextjs "$ci" "$part")" "$msg"
  check 0 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "part_mismatch[$which ci=$ci part=$part]: nothing written"
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
          check 1 "$([[ $ec -ne 0 && $got == 0 ]] && echo 1 || echo 0)" "$label: refused with nothing written"
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
check 0 "$(find "$T/ship0" -type f | wc -l | tr -d ' ')" "shipped_step0_fence_refuses_until_stack_is_set: nothing written"
run_step0 "$T/ship1" ts >/dev/null
before=$(find "$T/ship1" -type f | wc -l | tr -d ' ')
refuses_raw shipped_ci_fence_refuses_until_stack_is_set "$(raw_render "$CI_SNIPPET" "$T/ship1")" "unknown STACK"
check "$before" "$(find "$T/ship1" -type f | wc -l | tr -d ' ')" "shipped_ci_fence_refuses_until_stack_is_set: nothing written"
# a B3 STACK that differs from Step 0's is refused
mkdir -p "$T/mis1"; run_step0 "$T/mis1" ts >/dev/null
before=$(find "$T/mis1" -type f | wc -l | tr -d ' ')
refuses_raw ci_stack_differs_from_step0 "$(render_sc "$CI_SNIPPET" "$T/mis1" fastapi github)" "does not match"
check "$before" "$(find "$T/mis1" -type f | wc -l | tr -d ' ')" "ci_stack_differs_from_step0: nothing written"
# B3 without Step 0's lefthook.yml is refused too
mkdir -p "$T/mis2"
refuses_raw ci_without_step0_refused "$(render_sc "$CI_SNIPPET" "$T/mis2" nextjs github)" "does not match"
check 0 "$(find "$T/mis2" -type f | wc -l | tr -d ' ')" "ci_without_step0_refused: nothing written"

# ── searchable directories, rm and mkdir failures, relative targets, manifest message ──
if [[ "$(id -u)" != 0 ]]; then
  # a directory that is writable but not searchable is refused before any write
  for pair in ".lefthook:0666" ".claude:0600"; do
    d=${pair%%:*}; m=${pair##*:}
    tgt="$T/nosearch$d"; mkdir -p "$tgt/$d"; chmod "$m" "$tgt/$d"
    refuses_raw "prewrite_check_refuses_unsearchable_dir[$d $m]" "$(render_sc "$STEP0" "$tgt" nextjs "")" "not writable"
    chmod 0755 "$tgt/$d"
    check 0 "$(find "$tgt" -type f | wc -l | tr -d ' ')" "prewrite_check_refuses_unsearchable_dir[$d $m]: zero files written"
  done
  # the seed-neither fence reports a failed rm and leaves the gate in place
  tgt="$T/rmfail"; mkdir -p "$tgt"; run_step0 "$tgt" ts >/dev/null; chmod 0555 "$tgt/.claude"
  refuses_raw seed_neither_reports_a_failed_rm "$(render_sc "$NEITHER" "$tgt" nextjs "")" "rm failed"
  check 1 "$([[ -f "$tgt/.claude/ci-gates.sh" ]] && echo 1 || echo 0)" "seed_neither_reports_a_failed_rm: the gate is still there"
  chmod 0755 "$tgt/.claude"
fi
# a failing mkdir after the pre-checks stops with the state report (mkdir stubbed to fail)
printf '#!/usr/bin/env bash\necho "stub mkdir failure" >&2\nexit 1\n' > "$T/stubs/mkdir"; chmod +x "$T/stubs/mkdir"
for which in STEP0 CI; do
  tgt="$T/mkfail-$which"; mkdir -p "$tgt"
  snip=$STEP0; ci=""
  if [[ $which == CI ]]; then snip=$CI_SNIPPET; ci=github; bash -c "$(render_sc "$STEP0" "$tgt" nextjs "")" >/dev/null 2>&1; fi
  before=$(find "$tgt" -type f | wc -l | tr -d ' ')
  out=$(PATH="$T/stubs:$PATH" bash -c "$(render_sc "$snip" "$tgt" nextjs "$ci")" 2>&1); ec=$?
  check 1 "$([[ $ec -ne 0 && "$out" == *"mkdir failed"* && "$out" == *"$STOPLINE"* ]] && echo 1 || echo 0)" "mkdir_failure_stops[$which]: nonzero, names mkdir, ends with the stop line ($out)"
  check "$before" "$(find "$tgt" -type f | wc -l | tr -d ' ')" "mkdir_failure_stops[$which]: nothing was written"
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

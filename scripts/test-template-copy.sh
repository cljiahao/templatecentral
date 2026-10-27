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
trap 'rm -rf "$T"' EXIT

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

# render <snippet-text> <target> <selector> — substitute the placeholders, set SEL, and keep only
# the cp lines whose tree appears in the selector (a space-separated list of tree names).
render() {
  printf '%s\n' "$1" | sed -e "s#<skill-dir>#$SK#g" -e "s#<target>#$2#g" -e "s#^SEL=.*#SEL=\"$3\"#" \
    | awk -v sel="$3" '
        BEGIN { n = split(sel, s, " ") }
        /^cp / && /shared\/template/ {
          for (i = 1; i <= n; i++) if (index($0, "shared/" s[i] "/.") > 0) { print; next }
          next
        }
        { print }'
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
# a real top-level directory that already holds other files is fine
mkdir -p "$T/g10/.claude"; printf 'mine\n' > "$T/g10/.claude/own.txt"
out=$(run_step0 "$T/g10" ts); check 0 "$?" "copy_allows_existing_directory_with_other_files ($out)"
check mine "$(cat "$T/g10/.claude/own.txt")" "copy_allows_existing_directory_with_other_files: own file kept"
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

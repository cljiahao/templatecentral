#!/usr/bin/env bash
# scripts/seeded-bundle-size.test.sh — the seeded check-bundle-size gate: it fails over the gzip budget, fails closed without build output, and skips stacks with no browser bundle.
# Fixtures use incompressible files so the gzip size is known. A real run scaffolds nextjs and vite-react, installs, builds and measures the real output
# (public registry only, no key). shadcn components are not part of the template, so the real build uses tiny stand-ins for them.
# A missing tool for the real run fails the test; ALLOW_SKIP_REAL=1 skips it with a SKIPPED: line.
# Usage: bash scripts/seeded-bundle-size.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
GATE="$SH/template/scripts/check-bundle-size.sh"
BUDGET="$SH/template/.claude/bundle-budget.txt"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-bs.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

BASH_BIN=$(command -v bash)

# run <dir> [env]: sets OUT and EC from running the gate inside a fixture directory.
run() {
  local d=$1
  shift
  OUT=$(cd "$d" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u BUNDLE_DIR -u BUNDLE_BUDGET_FILE "$@" "$BASH_BIN" "$GATE" 2>&1)
  EC=$?
}
# blob <kb> <file>: an incompressible file of about <kb> KB, so its gzip size is about the same.
blob() {
  mkdir -p "$(dirname "$2")"
  head -c "$(($1 * 1024))" /dev/urandom > "$2"
}
# fixture <name> <stack> <budget-kb>: a project with the stack's config file and a budget file; sets D.
fixture() {
  D="$T/$1"
  mkdir -p "$D/.claude"
  case "$2" in
    nextjs) : > "$D/next.config.ts" ;;
    vite-react) : > "$D/vite.config.ts" ;;
  esac
  printf 'max_gzip_kb %s\n' "$3" > "$D/.claude/bundle-budget.txt"
}

fixture next-ok nextjs 100
blob 30 "$D/.next/static/chunks/main.js"
blob 20 "$D/.next/static/css/app.css"
run "$D"
check 0 "$EC" "control: nextjs output under the budget passes ($OUT)"
has "ok (nextjs" "$OUT" "control names the stack"

fixture next-big nextjs 100
blob 90 "$D/.next/static/chunks/big-chunk.js"
blob 30 "$D/.next/static/chunks/small.js"
blob 5 "$D/.next/static/css/app.css"
run "$D"
check 1 "$EC" "nextjs output over the budget fails"
has "budget 100 KB" "$OUT" "message gives the budget"
has "bytes gzip of JS and CSS" "$OUT" "message reports bytes, not a truncated KB"
has "KB rounded up" "$OUT" "message says the KB figure is rounded up"
has "big-chunk.js" "$OUT" "message lists the biggest file"
has "dynamic import" "$OUT" "message says how to fix it"
case "$OUT" in
  *big-chunk.js*small.js*app.css*) check ordered ordered "biggest files are listed largest first" ;;
  *) check ordered "$OUT" "biggest files are listed largest first" ;;
esac

fixture vite-ok vite-react 100
blob 40 "$D/dist/assets/index-abc.js"
blob 10 "$D/dist/assets/index-abc.css"
run "$D"
check 0 "$EC" "control: vite output under the budget passes ($OUT)"

fixture vite-big vite-react 50
blob 60 "$D/dist/assets/index-abc.js"
run "$D"
check 1 "$EC" "vite output over the budget fails"
has "index-abc.js" "$OUT" "vite message names the file"

fixture vite-types vite-react 10
blob 60 "$D/dist/assets/font.woff2"
blob 60 "$D/dist/assets/index.js.map"
blob 1 "$D/dist/assets/index.js"
run "$D"
check 0 "$EC" "fonts and source maps are not counted ($OUT)"

fixture next-nobuild nextjs 100
run "$D"
check 2 "$EC" "no build output cannot be measured (exit 2)"
has "Build first" "$OUT" "message says to build first"

fixture next-nojs nextjs 100
mkdir -p "$D/.next/static/media"
blob 1 "$D/.next/static/media/logo.png"
run "$D"
check 2 "$EC" "a build folder with no JS or CSS cannot be measured"
has "no .js or .css files" "$OUT" "message says nothing was found"

fixture no-budget vite-react 100
rm "$D/.claude/bundle-budget.txt"
blob 1 "$D/dist/a.js"
run "$D"
check 2 "$EC" "a missing budget file cannot be measured"
has "bundle-budget.txt is missing" "$OUT" "message names the budget file"

fixture bad-budget vite-react 100
blob 1 "$D/dist/a.js"
for bad in lots 0 -5 "" 007 1.5 "5 0" 12345678901234567890 1234567; do
  printf 'max_gzip_kb %s\n' "$bad" > "$D/.claude/bundle-budget.txt"
  run "$D"
  check 2 "$EC" "budget '$bad' is rejected"
  has "needs a line 'max_gzip_kb <whole number above 0, 6 digits at most, no leading zeros>'" "$OUT" "budget '$bad' message says the fix"
done
printf '# no key here\n' > "$D/.claude/bundle-budget.txt"
run "$D"
check 2 "$EC" "a budget file without the key is rejected"

# Budget-file parser parity with gate-ratchet.sh: every form the ratchet reads differently or refuses is refused here too, so the two never disagree in the unsafe direction (the gate passing a budget the ratchet would flag).
# budget_text <label> <text as printf %b> <want exit>: the budget file holds exactly this text.
budget_text() {
  printf '%b' "$2" > "$D/.claude/bundle-budget.txt"
  run "$D"
  check "$3" "$EC" "budget file '$1' exits $3 ($OUT)"
}
fixture parser vite-react 100
blob 1 "$D/dist/a.js"
budget_text "control: one clean line" 'max_gzip_kb 100\n' 0
budget_text "no trailing newline" 'max_gzip_kb 100' 0
budget_text "duplicate key" 'max_gzip_kb 100\nmax_gzip_kb 900\n' 2
has "more than one max_gzip_kb line" "$OUT" "duplicate key message says why"
budget_text "key with a colon" 'max_gzip_kb: 900\n' 2
budget_text "key with an equals sign" 'max_gzip_kb=900\n' 2
budget_text "plus sign" 'max_gzip_kb +900\n' 2
budget_text "hex" 'max_gzip_kb 0x384\n' 2
budget_text "exponent" 'max_gzip_kb 4e3\n' 2
budget_text "leading zero" 'max_gzip_kb 0900\n' 2
budget_text "huge value" 'max_gzip_kb 99999999999999999999\n' 2
budget_text "empty file" '' 2
budget_text "carriage return" 'max_gzip_kb 100\r\n' 2
has "carriage return in " "$OUT" "CRLF message names the cause"
has "/.claude/bundle-budget.txt: save it with LF" "$OUT" "CRLF message names the file and the fix"
budget_text "carriage return mid-file" '# note\r\nmax_gzip_kb 100\n' 2

# The folder the gate reads is fixed and fresh: tracked build output is refused, and a build that wrote somewhere else leaves nothing to measure.
# git_fixture <name> <stack> <budget-kb>: a fixture that is a git repository.
git_fixture() {
  fixture "$1" "$2" "$3"
  (cd "$D" && git init -q . > /dev/null 2>&1)
}
git_fixture tracked-ok vite-react 100
blob 5 "$D/dist/a.js"
run "$D"
check 0 "$EC" "control: untracked build output in a git project passes ($OUT)"
git_fixture tracked-dist vite-react 100
blob 5 "$D/dist/a.js"
(cd "$D" && git add -f dist/a.js > /dev/null 2>&1)
run "$D"
check 2 "$EC" "a tracked dist is refused"
has "build output is tracked by git (dist/a.js)" "$OUT" "message names the tracked file"
git_fixture tracked-next nextjs 100
blob 5 "$D/.next/static/a.js"
(cd "$D" && git add -f .next/static/a.js > /dev/null 2>&1)
run "$D"
check 2 "$EC" "a tracked .next is refused"
has "build output is tracked by git" "$OUT" "message says it is tracked"
git_fixture tracked-other nextjs 100
blob 5 "$D/dist/a.js"
(cd "$D" && git add -f dist/a.js > /dev/null 2>&1)
run "$D"
check 2 "$EC" "a tracked dist is refused on a Next.js project too, whatever the stack reads"
fixture outdir vite-react 100
blob 5 "$D/build/a.js"
run "$D"
check 2 "$EC" "a build written to another folder (build.outDir) leaves dist missing and exits 2"
has "no build output at dist" "$OUT" "message names the folder the gate reads"
fixture emptydir vite-react 100
mkdir -p "$D/dist"
run "$D"
check 2 "$EC" "an empty dist exits 2"
has "no .js or .css files under dist" "$OUT" "message says the folder holds nothing to measure"
fixture nextdistmissing nextjs 100
blob 5 "$D/dist/a.js"
run "$D"
check 2 "$EC" "a Next.js build with no .next/static exits 2 even when dist holds files"
has "no build output at .next/static" "$OUT" "message names the folder the gate reads"

# The stack comes from harness.json (a frozen file): a browser stack with no config in the folder is never a skip.
# recorded <name> <stack in harness.json> [config file]: a project whose harness.json records <stack>.
recorded() {
  D="$T/$1"
  mkdir -p "$D/.claude"
  printf '{\n  "templatecentral_version": "8.0.0",\n  "stack": "%s",\n  "seeded_at": "2026-01-01"\n}\n' "$2" > "$D/.claude/harness.json"
  printf 'max_gzip_kb 100\n' > "$D/.claude/bundle-budget.txt"
  if [ -n "${3:-}" ]; then : > "$D/$3"; fi
}
recorded rec-vite vite-react vite.config.ts
blob 5 "$D/dist/a.js"
run "$D"
check 0 "$EC" "control: recorded vite-react with its config measures ($OUT)"
recorded rec-next-moved nextjs
mkdir -p "$D/apps/web"
: > "$D/apps/web/next.config.ts"
echo '{"dependencies":{}}' > "$D/package.json"
blob 5 "$D/apps/web/.next/static/a.js"
run "$D"
check 2 "$EC" "recorded nextjs with the app moved into a subfolder and the root package.json emptied is not a skip"
has "records the stack as nextjs" "$OUT" "message names the recorded stack"
has "BUNDLE_DIR" "$OUT" "message says how to point the gate at the subfolder"
run "$D" BUNDLE_DIR=apps/web
check 0 "$EC" "the same project passes once BUNDLE_DIR names the subfolder ($OUT)"
recorded rec-vite-moved vite-react
run "$D"
check 2 "$EC" "recorded vite-react with no vite config is not a skip"
recorded rec-fastapi fastapi
run "$D"
check 0 "$EC" "recorded fastapi still skips ($OUT)"
has "skipped" "$OUT" "fastapi skip names the reason"
recorded rec-nestjs nestjs
run "$D"
check 0 "$EC" "recorded nestjs still skips ($OUT)"

fixture override vite-react 1
blob 5 "$D/dist/a.js"
run "$D"
check 1 "$EC" "control for the override: over a 1 KB budget"
printf 'max_gzip_kb 100\n' > "$D/other-budget.txt"
run "$D" BUNDLE_BUDGET_FILE=other-budget.txt
check 0 "$EC" "BUNDLE_BUDGET_FILE points the gate at another budget ($OUT)"

# Six digits is the cap; a trailing comment is allowed.
printf 'max_gzip_kb 999999\n' > "$D/.claude/bundle-budget.txt"
run "$D"
check 0 "$EC" "a 6-digit budget is accepted ($OUT)"
printf 'max_gzip_kb 100 # raised for the charts page\n' > "$D/.claude/bundle-budget.txt"
run "$D"
check 0 "$EC" "a trailing comment on the budget line is accepted ($OUT)"
printf 'max_gzip_kb 1 # tight\n' > "$D/.claude/bundle-budget.txt"
run "$D"
check 1 "$EC" "the number before the comment is the budget"

# A budget-file override widens the gate, so CI refuses it.
printf 'max_gzip_kb 100\n' > "$D/other-budget.txt"
for ci in GITHUB_ACTIONS=true TF_BUILD=True; do
  run "$D" "$ci" BUNDLE_BUDGET_FILE=other-budget.txt
  check 2 "$EC" "BUNDLE_BUDGET_FILE is refused with $ci"
  has "not allowed in CI" "$OUT" "refusal under $ci says why"
done
run "$D" BUNDLE_BUDGET_FILE=other-budget.txt
check 0 "$EC" "BUNDLE_BUDGET_FILE is allowed outside CI ($OUT)"
run "$D" GITHUB_ACTIONS=true
check 1 "$EC" "without the override, CI still measures against the seeded budget file"

# A sub-KB overshoot must not round down to a pass.
fixture round vite-react 1
mkdir -p "$D/dist"
head -c 1500 /dev/urandom > "$D/dist/a.js"
run "$D"
check 1 "$EC" "about 1.5 KB gzip fails a 1 KB budget (rounded up, not truncated)"

# BUNDLE_DIR: the frontend lives in a subfolder.
D="$T/mono"
mkdir -p "$D/.claude" "$D/backend" "$D/frontend"
echo '{"dependencies":{"next":"16"}}' > "$D/frontend/package.json"
: > "$D/frontend/next.config.ts"
printf 'max_gzip_kb 100\n' > "$D/.claude/bundle-budget.txt"
blob 20 "$D/frontend/.next/static/a.js"
run "$D" BUNDLE_DIR=frontend
check 0 "$EC" "BUNDLE_DIR points the gate at the frontend folder ($OUT)"
run "$D" BUNDLE_DIR=nowhere
check 2 "$EC" "BUNDLE_DIR that is not a folder cannot measure"
has "BUNDLE_DIR 'nowhere' is not a folder" "$OUT" "message names the folder"
printf 'max_gzip_kb 1\n' > "$D/.claude/bundle-budget.txt"
run "$D" BUNDLE_DIR=frontend
check 1 "$EC" "BUNDLE_DIR with a tight budget fails over budget"

# package.json depends on next or vite but no config is found: never a silent skip.
D="$T/noconfig-next"
mkdir -p "$D"
echo '{"dependencies":{"next":"16"}}' > "$D/package.json"
run "$D"
check 2 "$EC" "package.json with next and no next.config.* cannot be measured, not skipped"
has "depends on next or vite, but there is no next.config.* or vite.config.*" "$OUT" "message names the problem"
has "BUNDLE_DIR" "$OUT" "message says how to fix it"
D="$T/noconfig-vite"
mkdir -p "$D"
echo '{"devDependencies":{"vite":"8"}}' > "$D/package.json"
run "$D"
check 2 "$EC" "package.json with vite and no vite.config.* cannot be measured, not skipped"
D="$T/node-only"
mkdir -p "$D"
echo '{"dependencies":{"@nestjs/core":"11"}}' > "$D/package.json"
run "$D"
check 0 "$EC" "package.json with neither next nor vite is skipped ($OUT)"

D="$T/nest"
mkdir -p "$D"
echo '{}' > "$D/nest-cli.json"
run "$D"
check 0 "$EC" "a nestjs project is skipped ($OUT)"
has "skipped" "$OUT" "skip says why in one line"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "skip is one line"
D="$T/py"
mkdir -p "$D"
echo fastapi > "$D/requirements.txt"
run "$D"
check 0 "$EC" "a fastapi project is skipped ($OUT)"

real_ok=1
for tool in pnpm python3; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    real_ok=0
    if [ "${ALLOW_SKIP_REAL:-}" = 1 ]; then
      echo "SKIPPED: $tool is not installed, so the real scaffold builds did NOT happen and the gate was NOT proven on a real build (ALLOW_SKIP_REAL=1)."
    else
      FAIL=$((FAIL + 1))
      echo "FAIL: $tool is not installed, so the real scaffold builds cannot happen. Install it, or set ALLOW_SKIP_REAL=1 to skip them on purpose."
    fi
  fi
done

# stub_ui <dir>: the template leaves shadcn components to `shadcn add`; write minimal stand-ins for the ones the source imports.
stub_ui() {
  python3 -I - "$1" << 'PYEOF'
import glob, os, re, sys
root = sys.argv[1]
names = {}
for f in glob.glob(os.path.join(root, "src", "**", "*.ts*"), recursive=True):
    text = open(f, encoding="utf-8").read()
    for m in re.finditer(r"import\s+(?:type\s+)?\{([^}]*)\}\s+from\s+'@/components/ui/([a-z-]+)'", text):
        for n in m.group(1).split(","):
            n = n.replace("type ", "").split(" as ")[0].strip()
            if n:
                names.setdefault(m.group(2), set()).add(n)
out = os.path.join(root, "src", "components", "ui")
os.makedirs(out, exist_ok=True)
for mod, ns in names.items():
    body = "/* eslint-disable */\nconst C = (p: Record<string, any>) => <div {...(p as object)} />;\n"
    for n in sorted(ns):
        body += "export const %s = C;\n" % n
    open(os.path.join(out, mod + ".tsx"), "w", encoding="utf-8").write(body)
PYEOF
}

# real_build <stack> <name>: scaffold, install and build one stack; sets D, returns the build status.
real_build() {
  D="$T/$2"
  mkdir -p "$D"
  TC_STACK=$1 TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null || return 1
  mkdir -p "$D/.claude"
  cp "$BUDGET" "$D/.claude/bundle-budget.txt"
  cd "$D" || return 1
  pnpm install > "$T/$2-install.log" 2>&1 || return 1
  cd "$OLDPWD" || return 1
  stub_ui "$D" || return 1
  (cd "$D" && env NEXT_TELEMETRY_DISABLED=1 pnpm build > "$T/$2-build.log" 2>&1)
}

if [ "$real_ok" -eq 1 ]; then
  for pair in nextjs:real-next vite-react:real-vite; do
    stack=${pair%%:*}
    name=${pair##*:}
    real_build "$stack" "$name"
    check 0 $? "$stack scaffold installs and builds: $(tail -n 4 "$T/$name-build.log" 2> /dev/null | tr '\n' ' ')"
    run "$D"
    check 0 "$EC" "real $stack build is within the seeded budget ($OUT)"
    echo "real run $stack: $OUT"
    printf 'max_gzip_kb 20\n' > "$D/tight.txt"
    run "$D" BUNDLE_BUDGET_FILE=tight.txt
    check 1 "$EC" "real $stack build fails a 20 KB budget"
    has "check-bundle-size: biggest files:" "$OUT" "real failure lists the biggest files"
    echo "real run $stack over a 20 KB budget:"
    printf '%s\n' "$OUT"
    rm -rf "$D/.next" "$D/dist"
    run "$D"
    check 2 "$EC" "real $stack project without a build cannot be measured"
    has "Build first" "$OUT" "real failure says to build first"
  done
fi

echo "seeded-bundle-size.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

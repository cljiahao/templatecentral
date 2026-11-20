#!/usr/bin/env bash
# scripts/seeded-bundle-size.test.sh — the seeded check-bundle-size gate: it fails over the gzip budget, fails closed without build output, and skips stacks with no browser bundle.
# Fixtures use incompressible files so the gzip size is known. A real run scaffolds nextjs and vite-react, installs, builds and measures the real output
# (public registry only, no key). shadcn components are not part of the template, so the real build uses tiny stand-ins for them.
# Without pnpm or python3 the real run prints a loud SKIP locally and fails when CI is set.
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
  OUT=$(cd "$d" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS "$@" "$BASH_BIN" "$GATE" 2>&1)
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
check 1 "$EC" "no build output fails closed"
has "Build first" "$OUT" "message says to build first"

fixture next-nojs nextjs 100
mkdir -p "$D/.next/static/media"
blob 1 "$D/.next/static/media/logo.png"
run "$D"
check 1 "$EC" "a build folder with no JS or CSS fails closed"
has "no .js or .css files" "$OUT" "message says nothing was found"

fixture no-budget vite-react 100
rm "$D/.claude/bundle-budget.txt"
blob 1 "$D/dist/a.js"
run "$D"
check 1 "$EC" "a missing budget file fails closed"
has "bundle-budget.txt is missing" "$OUT" "message names the budget file"

fixture bad-budget vite-react 100
blob 1 "$D/dist/a.js"
for bad in lots 0 -5 ""; do
  printf 'max_gzip_kb %s\n' "$bad" > "$D/.claude/bundle-budget.txt"
  run "$D"
  check 1 "$EC" "budget '$bad' fails closed"
done
has "max_gzip_kb" "$OUT" "message names the budget key"
printf '# no key here\n' > "$D/.claude/bundle-budget.txt"
run "$D"
check 1 "$EC" "a budget file without the key fails closed"

fixture override vite-react 1
blob 5 "$D/dist/a.js"
run "$D"
check 1 "$EC" "control for the override: over a 1 KB budget"
printf 'max_gzip_kb 100\n' > "$D/other-budget.txt"
run "$D" BUNDLE_BUDGET_FILE=other-budget.txt
check 0 "$EC" "BUNDLE_BUDGET_FILE points the gate at another budget ($OUT)"

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

in_ci=0
for v in "${CI:-}" "${TF_BUILD:-}" "${GITHUB_ACTIONS:-}"; do
  case "$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')" in "" | false | 0 | no) ;; *) in_ci=1 ;; esac
done
real_ok=1
for tool in pnpm python3; do
  command -v "$tool" > /dev/null 2>&1 || real_ok=0
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
  (cd "$D" && pnpm install > "$T/$2-install.log" 2>&1) || return 1
  stub_ui "$D" || return 1
  (cd "$D" && env -u CI NEXT_TELEMETRY_DISABLED=1 pnpm build > "$T/$2-build.log" 2>&1)
}

if [ "$real_ok" -eq 0 ]; then
  if [ "$in_ci" -eq 1 ]; then
    echo "seeded-bundle-size.test: FAIL pnpm or python3 is not available in CI, so the real run did not happen." >&2
    FAIL=$((FAIL + 1))
  else
    echo "SKIPPED: pnpm or python3 is not installed, so the real scaffold builds did NOT happen and the gate was NOT proven on a real build."
  fi
else
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
    check 1 "$EC" "real $stack project without a build fails closed"
    has "Build first" "$OUT" "real failure says to build first"
  done
fi

echo "seeded-bundle-size.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

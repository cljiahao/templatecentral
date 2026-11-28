#!/usr/bin/env bash
# scripts/seeded-import-layers.test.sh — the seeded check-import-layers gate: each rule blocks a bad change and a clean control passes.
# A stub lint-imports on the PATH prints a chosen result, so import-linter is not installed here. The real tool runs on a real scaffold in the release proof.
# CPU time is measured with the shell's times builtin, never wall time. Every run clears CI, GITHUB_ACTIONS and TF_BUILD.
# Usage: bash scripts/seeded-import-layers.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${GATE:-$REPO_ROOT/skills/scaffold/shared/template/scripts/check-import-layers.sh}"
PYPROJECT="$REPO_ROOT/skills/scaffold/fastapi/template/pyproject.toml"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
hasnt() { # hasnt <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] is in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-import-layers.XXXXXX") || exit 2
trap 'chmod -R u+rwx "$T" 2> /dev/null; rm -rf "$T"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

mkdir -p "$T/bin"
# The stub reads STUB_MODE: ok (one contract kept), broken (exit 1), zero (exit 0, no contract kept).
cat > "$T/bin/lint-imports" << 'STUB'
#!/usr/bin/env bash
case "${STUB_MODE:-ok}" in
  ok) echo "Contracts: 1 kept, 0 broken."; exit 0 ;;
  broken) echo "Contracts: 0 kept, 1 broken."; echo "api is not allowed to import utils"; exit 1 ;;
  zero) echo "Contracts: 0 kept, 0 broken."; exit 0 ;;
esac
exit 3
STUB
chmod 755 "$T/bin/lint-imports"

# run <dir> [VAR=value ...]: sets OUT and EC from the gate run with the stub tool on the PATH.
run() {
  local d=$1
  shift
  OUT=$(cd "$d" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$T/bin:$PATH" "$@" bash "$GATE" 2>&1)
  EC=$?
}

# new_app <name> [subdir]: a git repository holding a fastapi app with the seeded pyproject.toml; sets D and A (the app folder).
new_app() {
  D="$T/$1"
  A="$D/${2:-.}"
  mkdir -p "$A"
  git -C "$D" init -q -b main
  printf 'fastapi==0.115.0\n' > "$A/requirements.txt"
  cp "$PYPROJECT" "$A/pyproject.toml"
}

new_app control
run "$D"
check 0 "$EC" "control: a fastapi app with every contract kept passes ($OUT)"
has "ok (1 app(s), every contract kept)" "$OUT" "control prints the ok line"

new_app planted
run "$D" STUB_MODE=broken
check 1 "$EC" "a planted cross-layer import fails ($OUT)"
has "lint-imports exited 1" "$OUT" "the broken contract is named by the gate"
has "api is not allowed to import utils" "$OUT" "the linter output is shown"

new_app zero
run "$D" STUB_MODE=zero
check 1 "$EC" "a run that kept no contract fails ($OUT)"
has "reported no kept contract" "$OUT" "the zero-contract run is named"

new_app notool
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="/usr/bin:/bin" bash "$GATE" 2>&1)
EC=$?
check 1 "$EC" "a missing lint-imports fails, never skips ($OUT)"
has "lint-imports is not installed" "$OUT" "the missing tool is named"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'lint-imports is not installed')" "the missing tool prints one line"
hasnt "nothing checked" "$OUT" "a missing tool never says nothing checked"

new_app sub backend
printf '{"name":"web"}\n' > "$D/package.json"
run "$D"
check 0 "$EC" "an app in backend/ is found and passes ($OUT)"
has "ok (1 app(s)" "$OUT" "the subfolder app is counted"
run "$D" STUB_MODE=broken
check 1 "$EC" "an app in backend/ with a planted violation fails ($OUT)"
has "backend: lint-imports exited 1" "$OUT" "the failure names the backend folder"

new_app nocontract
printf '[project]\nname = "x"\ndependencies = ["fastapi"]\n' > "$A/pyproject.toml"
run "$D"
check 1 "$EC" "a fastapi app with no [tool.importlinter] fails ($OUT)"
has "no [tool.importlinter]" "$OUT" "the missing rule is named"

new_app nolayers
awk '/^\[\[tool\.importlinter\.contracts\]\]/ { exit } { print }' "$PYPROJECT" > "$A/pyproject.toml"
run "$D"
check 1 "$EC" "a pyproject.toml with the section but no contract fails ($OUT)"

new_app nopyproject
rm "$A/pyproject.toml"
run "$D"
check 1 "$EC" "a fastapi app with no pyproject.toml fails ($OUT)"
has "no pyproject.toml" "$OUT" "the missing file is named"

new_app symlinked
mv "$A/pyproject.toml" "$A/real.toml"
ln -s real.toml "$A/pyproject.toml"
run "$D"
check 1 "$EC" "a symlinked pyproject.toml fails closed ($OUT)"

new_app venv
mkdir -p "$A/.venv/bin"
printf '#!/usr/bin/env bash\necho "Contracts: 0 kept, 1 broken."\nexit 1\n' > "$A/.venv/bin/lint-imports"
chmod 755 "$A/.venv/bin/lint-imports"
run "$D"
check 1 "$EC" "the app's own .venv tool wins over the PATH ($OUT)"

new_app two backend
mkdir -p "$D/worker"
printf 'fastapi==0.115.0\n' > "$D/worker/requirements.txt"
run "$D"
check 1 "$EC" "a second fastapi app with no contract fails while the first passes ($OUT)"
has "worker: " "$OUT" "the failing app is named"

new_app tsonly
rm "$A/requirements.txt" "$A/pyproject.toml"
printf '{"name":"web"}\n' > "$A/package.json"
run "$D"
check 0 "$EC" "a TypeScript project has nothing to check ($OUT)"
has "nothing checked" "$OUT" "the nothing-checked line is distinct"

new_app newline
touch "$D/a"$'\n'"b"
run "$D"
check 2 "$EC" "a file name with a line break stops the gate ($OUT)"

OUT=$(cd "$T" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$T/bin:$PATH" bash "$GATE" 2>&1)
EC=$?
check 2 "$EC" "outside a git repository the gate cannot run ($OUT)"

# cpu time of one control run (shell and children, user+sys)
new_app cpu
times > "$T/t0"
run "$D"
times > "$T/t1"
echo "cpu (user+sys): before [$(tr '\n' ' ' < "$T/t0")] after [$(tr '\n' ' ' < "$T/t1")]"

echo "seeded-import-layers: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

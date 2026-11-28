#!/usr/bin/env bash
# scripts/seeded-boundaries.test.sh — tests for the seeded layer rules, accessibility lint and strict TypeScript flags, on a real tc-copy.sh scaffold of each stack.
# Each stack: a clean control passes; every probe fails with the expected message; the same probe passes once its rule is reverted; the gate ratchet and the workaround detector refuse a weakened rule.
# Packages come from the public npm and PyPI registries (no login), installed once per package.json or requirements file into a cache under TMPDIR.
# TC_TEST_BOUNDARIES_OFFLINE=1 skips every stack that needs an install and says so; without it a failed install exits 2.
# Usage: bash scripts/seeded-boundaries.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO_ROOT/skills/scaffold/shared"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
has_not() { # has_not <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] still in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/sb.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
CACHE=${TMPDIR:-/tmp}
GIT=(git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false)
SKIPPED=()

scaffold() { # scaffold <stack> <dir>: the same parts day-one.test.sh copies, committed on a base branch
  local st=$1 dir=$2 part
  mkdir -p "$dir"
  for part in stack base agents settings late; do
    TC_STACK=$st TC_PART=$part bash "$SHARED/tc-copy.sh" "$dir" > /dev/null 2>&1 || { echo "seeded-boundaries.test: tc-copy part $part failed for $st" >&2; exit 2; }
  done
  TC_STACK=$st TC_PART=ci TC_CI=github bash "$SHARED/tc-copy.sh" "$dir" > /dev/null 2>&1 || exit 2
  TC_STACK=$st TC_PART=manifest bash "$SHARED/tc-copy.sh" "$dir" > /dev/null 2>&1 || exit 2
  git -C "$dir" init -q -b main
  git -C "$dir" add -A
  "${GIT[@]}" -C "$dir" commit -q -m base
  git -C "$dir" checkout -q -b work
}

want_install() { # want_install <stack>: 0 to go on, 1 after a loud skip
  if [[ "${TC_TEST_BOUNDARIES_OFFLINE:-}" == 1 ]]; then
    echo "SKIPPED: $1 — TC_TEST_BOUNDARIES_OFFLINE=1, so its packages were NOT installed and none of its boundary, accessibility or type cases ran."
    SKIPPED+=("$1")
    return 1
  fi
  return 0
}

install_node() { # install_node <dir>: npm install into a cache keyed by the package.json hash, then link it in
  local dir=$1 key cache
  key=$(shasum "$dir/package.json" | cut -c1-12)
  cache="$CACHE/tc-seeded-boundaries-$(basename "$dir")-$key"
  if [[ ! -d "$cache/node_modules/.bin" ]]; then
    command -v npm > /dev/null 2>&1 || { echo "seeded-boundaries.test: npm is missing. Fix: install Node.js, or set TC_TEST_BOUNDARIES_OFFLINE=1 to skip." >&2; exit 2; }
    rm -rf "$cache.stage"
    mkdir -p "$cache.stage"
    node -e "const p=require('$dir/package.json');delete p.packageManager;require('fs').writeFileSync('$cache.stage/package.json',JSON.stringify(p))"
    if ! (cd "$cache.stage" && npm install --legacy-peer-deps --ignore-scripts --no-audit --no-fund --loglevel=error --cache "$cache.npm" > "$cache.log" 2>&1); then
      echo "seeded-boundaries.test: npm install for $(basename "$dir") failed: $(tail -n 1 "$cache.log"). Fix: check network access to the public npm registry, or set TC_TEST_BOUNDARIES_OFFLINE=1 to skip." >&2
      rm -rf "$cache.stage"
      exit 2
    fi
    rm -rf "$cache"
    mv "$cache.stage" "$cache"
  fi
  ln -s "$cache/node_modules" "$dir/node_modules"
}

ESLINT_REVERT='import base from "./eslint.config.mjs";
const all = [base].flat(Infinity);
const mode = process.env.REVERT;
export default all.map((e) => {
  if (!e.rules) return e;
  const text = JSON.stringify(e.rules);
  if (mode === "layers" && text.includes("Layer rule")) return { ...e, rules: {} };
  if (mode === "a11y") return { ...e, rules: Object.fromEntries(Object.entries(e.rules).filter(([k]) => !k.startsWith("jsx-a11y/"))) };
  return e;
});'

lint_probe() { # lint_probe <dir> <name> <file> <content> <want> <revert>: fails with <want>, passes with <revert> applied
  local dir=$1 name=$2 file=$3 content=$4 want=$5 revert=$6 out rc
  mkdir -p "$(dirname "$dir/$file")"
  printf '%s\n' "$content" > "$dir/$file"
  out=$(cd "$dir" && node_modules/.bin/eslint "$file" 2>&1)
  rc=$?
  check 1 "$rc" "$name fails lint"
  has "$want" "$out" "$name message"
  printf '%s\n' "$ESLINT_REVERT" > "$dir/eslint.revert.mjs"
  out=$(cd "$dir" && REVERT=$revert node_modules/.bin/eslint -c eslint.revert.mjs "$file" 2>&1)
  rc=$?
  check 0 "$rc" "$name passes once the rule is reverted [$out]"
  rm -f "$dir/$file" "$dir/eslint.revert.mjs"
}

tsc_probe() { # tsc_probe <dir> <name> <content> <want-code> <flag>: fails with <want-code> in the probe file, passes with --<flag> false
  local dir=$1 name=$2 content=$3 want=$4 flag=$5 out all rc
  printf '%s\n' "$content" > "$dir/src/probe-types.ts"
  all=$(tsc_in "$dir")
  rc=$?
  tsc_ran "$name" "$rc" "$all"
  out=$(printf '%s\n' "$all" | grep 'probe-types' || true)
  has "$want" "$out" "$name fails typecheck"
  all=$(tsc_in "$dir" "--$flag" false)
  rc=$?
  tsc_ran "$name with --$flag false" "$rc" "$all"
  out=$(printf '%s\n' "$all" | grep 'probe-types' || true)
  check "" "$out" "$name passes once --$flag is false"
  rm -f "$dir/src/probe-types.ts"
}

tsc_ran() { # tsc_ran <name> <status> <output>: a non-zero tsc status without any error line means it crashed, so nothing was checked
  case $3 in
    *"error TS"*) ;;
    *) check 0 "$2" "$1 typecheck ran [$3]" ;;
  esac
}

tsc_in() { # tsc_in <dir> [tsc flags]: the project typecheck output, stderr included
  local dir=$1
  shift
  cd "$dir" || return 1
  node_modules/.bin/tsc --noEmit -p tsconfig.json "$@" 2>&1
}

control() { # control <dir> <name>: lint of the whole project and typecheck, apart from files shadcn generates, pass
  local dir=$1 name=$2 out rc
  out=$(cd "$dir" && node_modules/.bin/eslint "${3:-.}" 2>&1)
  check 0 "$?" "$name clean control passes lint [$(echo "$out" | tail -n 3)]"
  out=$(tsc_in "$dir")
  rc=$?
  tsc_ran "$name" "$rc" "$out"
  out=$(printf '%s\n' "$out" | grep 'error TS' | grep -v "TS2307.*components/ui" || true)
  check "" "$out" "$name clean control passes typecheck"
}

ratchet_probe() { # ratchet_probe <dir> <name> <edit-command>: the edit is committed and the ratchet must report WEAKENED
  local dir=$1 name=$2 out rc
  git -C "$dir" reset -q --hard main
  (cd "$dir" && eval "$3")
  git -C "$dir" add -A
  "${GIT[@]}" -C "$dir" commit -q -m probe
  out=$(cd "$dir" && bash scripts/gate-ratchet.sh main 2>&1)
  rc=$?
  check 1 "$rc" "ratchet refuses: $name"
  has "WEAKENED" "$out" "ratchet names the weakening: $name"
  git -C "$dir" reset -q --hard main
}

ratchet_error() { # ratchet_error <dir> <name> <edit-command>: the edit is committed and the ratchet must stop with a config it cannot read, never report ok
  local dir=$1 name=$2 out rc
  git -C "$dir" reset -q --hard main
  (cd "$dir" && eval "$3")
  git -C "$dir" add -A
  "${GIT[@]}" -C "$dir" commit -q -m probe
  out=$(cd "$dir" && bash scripts/gate-ratchet.sh main 2>&1)
  rc=$?
  check 2 "$rc" "ratchet stops: $name"
  has "UNREADABLE" "$out" "ratchet names the unreadable config: $name"
  git -C "$dir" reset -q --hard main
}

ratchet_pass() { # ratchet_pass <dir> <name> <edit-command>: the edit is committed and the ratchet must report no weakening
  local dir=$1 name=$2 out rc
  git -C "$dir" reset -q --hard main
  (cd "$dir" && eval "$3")
  git -C "$dir" add -A
  "${GIT[@]}" -C "$dir" commit -q -m probe
  out=$(cd "$dir" && bash scripts/gate-ratchet.sh main 2>&1)
  rc=$?
  check 0 "$rc" "ratchet accepts: $name [$out]"
  git -C "$dir" reset -q --hard main
}

layers_bypass_probes() { # layers_bypass_probes <dir> <stack>: every way to stop eslint.config.mjs reading the layer rules is refused
  local dir=$1 st=$2 emptied="printf 'export default [];\\n' > other.mjs"
  ratchet_probe "$dir" "$st layers import repointed to a new file" "$emptied && sed -i.bak \"s|'./layers.config.mjs'|'./other.mjs'|\" eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$dir" "$st layers import renamed and repointed" "$emptied && sed -i.bak \"s|import layers from './layers.config.mjs'|import x from './other.mjs'|; s|^  ...layers,|  ...x,|\" eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$dir" "$st layers file pulls in another file" "$emptied && { printf \"import other from './other.mjs';\\n\"; cat layers.config.mjs; } > t.mjs && mv t.mjs layers.config.mjs"
  ratchet_error "$dir" "$st layers file exports another file instead of its blocks" "$emptied && { printf \"import other from './other.mjs';\\n\"; cat layers.config.mjs; } > t.mjs && mv t.mjs layers.config.mjs && sed -i.bak 's|^export default .*|export default other;|' layers.config.mjs && rm layers.config.mjs.bak"
  ratchet_probe "$dir" "$st layers spread filtered to nothing" "sed -i.bak 's|^  ...layers,|  ...layers.filter(() => false),|' eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$dir" "$st layers spread replaced by an empty array" "sed -i.bak 's|^  ...layers,|  ...[],|' eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_error "$dir" "$st layers import points at a file that does not exist" "sed -i.bak \"s|'./layers.config.mjs'|'./missing.mjs'|\" eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_pass "$dir" "$st an unrelated stricter rule" "awk '{ print } /^  ...layers,/ { print \"  { rules: { eqeqeq: \\\"error\\\" } },\" }' eslint.config.mjs > t.mjs && mv t.mjs eslint.config.mjs"
}

workaround_probe() { # workaround_probe <dir> <name> <file> <content>: an inline disable of a new rule is flagged
  local dir=$1 name=$2 file=$3 content=$4 out rc
  git -C "$dir" reset -q --hard main
  printf '%s\n' "$content" > "$dir/$file"
  git -C "$dir" add -A
  "${GIT[@]}" -C "$dir" commit -q -m probe
  out=$(cd "$dir" && bash scripts/check-workarounds.sh main 2>&1)
  rc=$?
  check 1 "$rc" "workaround detector flags: $name"
  has "$file:1" "$out" "workaround detector names the line: $name"
  git -C "$dir" reset -q --hard main
}

# nextjs
st=nextjs
if want_install $st; then
  D="$T/$st"
  scaffold $st "$D"
  install_node "$D"
  control "$D" $st .
  lint_probe "$D" "$st lib imports a component" src/lib/probe-layer.ts "import { x } from '@/components/ui/button';
export const y = x;" "lib may import only @/lib" layers
  lint_probe "$D" "$st deep relative climb" src/components/layout/probe-climb.tsx "import { y } from '../../lib/utils';
export const z = y;" "may not leave its components folder" layers
  lint_probe "$D" "$st deep feature import" src/app/probe-deep.ts "import { z } from '@/features/auth/internal/store';
export const y = z;" "app may import only" layers
  lint_probe "$D" "$st dynamic import" src/lib/probe-dyn.ts "export const load = () => import('@/features/auth');" "lib may import only" layers
  lint_probe "$D" "$st wrong-layer re-export" src/lib/probe-barrel.ts "export * from '@/app/layout';" "lib may import only" layers
  lint_probe "$D" "$st img without alt" src/components/layout/probe-a11y.tsx "export const A = () => <img src=\"/a.png\" />;" "jsx-a11y/alt-text" a11y
  tsc_probe "$D" "$st unchecked index" "export const first = (xs: string[]): number => xs[0].length;" "probe-types.ts" noUncheckedIndexedAccess
  tsc_probe "$D" "$st missing override" "class Base { run(): void {} }
export class Sub extends Base { run(): void {} }" "TS4114" noImplicitOverride
  ratchet_probe "$D" "$st a11y preset dropped" "sed -i.bak \"s|rules: { ...jsxA11y.flatConfigs.recommended.rules } }|rules: {} }|\" eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$D" "$st layer blocks dropped" "sed -i.bak 's|^  ...layers,||' eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$D" "$st layer rule turned off" "sed -i.bak \"s|'no-restricted-imports': \\['error'|'no-restricted-imports': ['off'|\" layers.config.mjs && rm layers.config.mjs.bak"
  layers_bypass_probes "$D" "$st"
  ratchet_probe "$D" "$st path-wide ignore" "sed -i.bak \"s|^const config = \[|const config = [ { ignores: ['src/**'] },|\" eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$D" "$st type flag removed" "sed -i.bak '/noUncheckedIndexedAccess/d' tsconfig.json && rm tsconfig.json.bak"
  ratchet_probe "$D" "$st type flag turned off" "sed -i.bak 's/\"noImplicitOverride\": true/\"noImplicitOverride\": false/' tsconfig.json && rm tsconfig.json.bak"
  workaround_probe "$D" "$st inline a11y disable" src/probe-disable.tsx "export const A = () => <img src=\"/a.png\" />; // eslint-disable-line jsx-a11y/alt-text"
fi

# vite-react
st=vite-react
if want_install $st; then
  D="$T/$st"
  scaffold $st "$D"
  install_node "$D"
  control "$D" $st .
  lint_probe "$D" "$st lib imports a feature" src/lib/probe-layer.ts "import { x } from '@/features/auth';
export const y = x;" "lib may import only @/lib" layers
  lint_probe "$D" "$st deep relative climb" src/features/auth/probe-climb.ts "import { y } from '../../pages/home';
export const z = y;" "may not leave its feature folder" layers
  lint_probe "$D" "$st deep feature import" src/pages/probe-deep.ts "import { z } from '@/features/auth/internal/store';
export const y = z;" "pages may import only" layers
  lint_probe "$D" "$st dynamic import" src/lib/probe-dyn.ts "export const load = () => import('@/pages/home');" "lib may import only" layers
  lint_probe "$D" "$st wrong-layer re-export" src/lib/probe-barrel.ts "export * from '@/pages/home';" "lib may import only" layers
  lint_probe "$D" "$st img without alt" src/components/layout/probe-a11y.tsx "export const A = () => <img src=\"/a.png\" />;" "jsx-a11y/alt-text" a11y
  tsc_probe "$D" "$st unchecked index" "export const first = (xs: string[]): number => xs[0].length;" "probe-types.ts" noUncheckedIndexedAccess
  tsc_probe "$D" "$st missing override" "class Base { run(): void {} }
export class Sub extends Base { run(): void {} }" "TS4114" noImplicitOverride
  ratchet_probe "$D" "$st a11y preset dropped" "sed -i.bak 's|^      ...jsxA11y.flatConfigs.recommended.rules,||' eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$D" "$st layer blocks dropped" "sed -i.bak 's|^  ...layers,||' eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$D" "$st layer rule turned off" "sed -i.bak \"s|'no-restricted-imports': \\['error'|'no-restricted-imports': ['off'|\" layers.config.mjs && rm layers.config.mjs.bak"
  layers_bypass_probes "$D" "$st"
  ratchet_probe "$D" "$st type flag turned off" "sed -i.bak 's/\"noImplicitOverride\": true/\"noImplicitOverride\": false/' tsconfig.json && rm tsconfig.json.bak"
  workaround_probe "$D" "$st inline a11y disable" src/probe-disable.tsx "export const A = () => <img src=\"/a.png\" />; // eslint-disable-line jsx-a11y/alt-text"
fi

# nestjs
st=nestjs
if want_install $st; then
  D="$T/$st"
  scaffold $st "$D"
  install_node "$D"
  control "$D" $st "{src,test}/**/*.ts"
  lint_probe "$D" "$st common imports a module" src/common/probe-layer.ts "import '../modules/example/example.service';" "common may import nothing outside src/common" layers
  lint_probe "$D" "$st module imports a sibling repository" src/modules/base/probe-sibling.ts "import { ExampleRepository } from '../example/example.repository';
export const y = ExampleRepository;" "module may import only common, config" layers
  lint_probe "$D" "$st deep relative climb" src/modules/example/probe-climb.ts "import '../../../package.json';" "module may import only common, config" layers
  lint_probe "$D" "$st dynamic import" src/config/probe-dyn.ts "export const load = () => import('../modules/example/example.service');" "config may import nothing outside src/config" layers
  lint_probe "$D" "$st wrong-layer re-export" src/config/probe-barrel.ts "export * from '../modules';" "config may import nothing outside src/config" layers
  tsc_probe "$D" "$st unchecked index" "export const first = (xs: string[]): number => xs[0].length;" "probe-types.ts" noUncheckedIndexedAccess
  tsc_probe "$D" "$st missing override" "class Base { run(): void {} }
export class Sub extends Base { run(): void {} }" "TS4114" noImplicitOverride
  tsc_probe "$D" "$st index-signature dot access" "const m: Record<string, string> = {};
export const v = m.key;" "TS4111" noPropertyAccessFromIndexSignature
  ratchet_probe "$D" "$st layer blocks dropped" "sed -i.bak 's|^  ...layers,||' eslint.config.mjs && rm eslint.config.mjs.bak"
  ratchet_probe "$D" "$st layer rule turned off" "sed -i.bak \"s|'no-restricted-imports': \\['error'|'no-restricted-imports': ['off'|\" layers.config.mjs && rm layers.config.mjs.bak"
  layers_bypass_probes "$D" "$st"
  ratchet_probe "$D" "$st type flag removed" "sed -i.bak '/noUncheckedIndexedAccess/d' tsconfig.json && rm tsconfig.json.bak"
  workaround_probe "$D" "$st inline layer-rule disable" src/probe-disable.ts "import { x } from './modules/example/example.service'; // eslint-disable-line no-restricted-imports"
fi

# fastapi
st=fastapi
if want_install $st; then
  D="$T/$st"
  scaffold $st "$D"
  req="$D/requirements-dev.txt"
  key=$(shasum "$req" "$D/pyproject.toml" | shasum | cut -c1-12)
  venv="$CACHE/tc-seeded-boundaries-fastapi-$key"
  if [[ ! -x "$venv/bin/lint-imports" ]]; then
    rm -rf "$venv"
    pins=$(grep -E '^(import-linter|ruff)' "$req" | tr '\n' ' ')
    if command -v uv > /dev/null 2>&1; then
      # shellcheck disable=SC2086
      { UV_CACHE_DIR="$CACHE/tc-seeded-boundaries-uv" uv venv -q --python ">=3.10" "$venv" && UV_CACHE_DIR="$CACHE/tc-seeded-boundaries-uv" uv pip install -q --python "$venv/bin/python" $pins; } > "$venv.log" 2>&1
    else
      py=""
      for cand in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
        if command -v "$cand" > /dev/null 2>&1 && "$cand" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2> /dev/null; then py=$cand; break; fi
      done
      [[ -n "$py" ]] || { echo "seeded-boundaries.test: no Python 3.10 or newer found (import-linter needs it). Fix: install one, or set TC_TEST_BOUNDARIES_OFFLINE=1 to skip." >&2; exit 2; }
      # shellcheck disable=SC2086
      { "$py" -m venv "$venv" && "$venv/bin/python" -m pip install -q --disable-pip-version-check $pins; } > "$venv.log" 2>&1
    fi
    if [[ ! -x "$venv/bin/lint-imports" ]]; then
      echo "seeded-boundaries.test: installing $pins failed: $(tail -n 1 "$venv.log"). Fix: check network access to PyPI, or set TC_TEST_BOUNDARIES_OFFLINE=1 to skip." >&2
      rm -rf "$venv"
      exit 2
    fi
  fi
  RUFF="$venv/bin/ruff"
  LI="$venv/bin/lint-imports"
  li() { (cd "$D" && PYTHONPATH=src "$LI" --config "${1:-pyproject.toml}" 2>&1); }
  out=$(cd "$D" && "$RUFF" check src test 2>&1)
  check 0 "$?" "$st clean control passes ruff [$out]"
  out=$(li)
  check 0 "$?" "$st clean control passes import-linter [$(echo "$out" | tail -n 2)]"
  printf 'from api.routes import router\n' > "$D/src/core/probe_layer.py"
  out=$(li)
  check 1 "$?" "$st core imports api fails import-linter"
  has "core is not allowed to import api" "$out" "$st layer message"
  has "Layer rule (docs/architecture.md)" "$out" "$st contract names the layer rule"
  sed 's/^layers = .*/layers = ["api"]/' "$D/pyproject.toml" > "$D/pyproject.revert.toml"
  out=$(li pyproject.revert.toml)
  check 0 "$?" "$st core-imports-api passes once the contract is reverted [$(echo "$out" | tail -n 2)]"
  rm -f "$D/src/core/probe_layer.py" "$D/pyproject.revert.toml"
  printf 'from ..api import tags\n' > "$D/src/models/probe_relative.py"
  out=$(cd "$D" && "$RUFF" check src/models/probe_relative.py 2>&1)
  check 1 "$?" "$st parent-relative import fails ruff"
  has "TID252" "$out" "$st relative-import message"
  out=$(cd "$D" && "$RUFF" check --ignore TID252 src/models/probe_relative.py 2>&1)
  has_not "TID252" "$out" "$st relative import is clean of TID252 once ignored"
  rm -f "$D/src/models/probe_relative.py"
  printf 'import importlib\nmod = importlib.import_module("api.routes")\n' > "$D/src/utils/probe_dynamic.py"
  out=$(cd "$D" && "$RUFF" check src/utils/probe_dynamic.py 2>&1)
  check 1 "$?" "$st importlib fails ruff"
  has "Layer rule (docs/architecture.md)" "$out" "$st importlib message names the layer rule"
  out=$(cd "$D" && "$RUFF" check --ignore TID251 src/utils/probe_dynamic.py 2>&1)
  has_not "TID251" "$out" "$st importlib is clean of TID251 once ignored"
  rm -f "$D/src/utils/probe_dynamic.py"
  ratchet_probe "$D" "$st layer rules dropped from ruff select" "sed -i.bak 's|^  \"TID251\", \"TID252\",||' pyproject.toml && rm pyproject.toml.bak"
  ratchet_probe "$D" "$st relative-import ban loosened" "sed -i.bak 's|^ban-relative-imports = \"all\"|ban-relative-imports = \"parents\"|' pyproject.toml && rm pyproject.toml.bak"
  workaround_probe "$D" "$st inline layer-rule noqa" src/probe_noqa.py "import importlib  # noqa: TID251"
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then echo "seeded-boundaries.test: SKIPPED stacks: ${SKIPPED[*]}"; fi
echo "seeded-boundaries.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

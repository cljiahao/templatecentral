#!/usr/bin/env bash
# SBOM: writes a CycloneDX JSON bill of materials to dist/sbom/bom.cdx.json (SBOM_OUT overrides the path).
# pnpm projects use `pnpm sbom` on the lockfile (every dependency group: a bundler ships a devDependency that the code imports). Python projects are built from the project's own environment (VIRTUAL_ENV, else .venv)
# by py-env.py (shared with check-licences.sh), from the installed package metadata, checked against requirements.txt when there is one. Nothing is downloaded, uploaded or signed in to.
# Limit: a requirements.txt line behind a marker that applies here but is not installed passes silently, and the SBOM omits it.
# A project with both manifests gets two files, <name>-pnpm.json and <name>-python.json, and no <name>.json.
# Components and dependencies are sorted, so two runs on one lockfile differ only in serialNumber and metadata.timestamp.
# Each document is parsed before it is kept: it must be CycloneDX with a components array that is not empty when the lockfile lists dependencies.
# Exit: 0 written, 1 the document does not match the lockfile, 2 it could not be generated.
# Usage: bash scripts/generate-sbom.sh
set -uo pipefail

out=${SBOM_OUT:-dist/sbom/bom.cdx.json}
helper=$(dirname "${BASH_SOURCE[0]}")/py-env.py

die() {
  printf 'generate-sbom: %s\n' "$1" >&2
  exit 2
}
fail() {
  printf 'generate-sbom: %s\n' "$1" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/generate-sbom.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

# Parses the pnpm SBOM $1, rejects an invalid or empty one, and writes it sorted to $2: pnpm lists components in a different order on each run.
check_and_sort_pnpm() {
  local rc=''
  node -e '
    const fs = require("fs");
    const stop = (m) => { console.error(m); process.exit(3); };
    const byRef = (a, b) => String(a["bom-ref"] || a.ref).localeCompare(String(b["bom-ref"] || b.ref));
    const sortComponents = (list) => {
      list.sort(byRef);
      for (const c of list) if (Array.isArray(c.components)) sortComponents(c.components);
    };
    let j;
    try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { stop("pnpm sbom did not write valid JSON."); }
    if (!j || j.bomFormat !== "CycloneDX") stop("pnpm sbom wrote no CycloneDX document (bomFormat is missing).");
    if (!Array.isArray(j.components)) stop("the SBOM has no components array.");
    let need = 0;
    try { need = Object.keys(JSON.parse(fs.readFileSync("package.json", "utf8")).dependencies || {}).length; } catch (e) { stop("cannot read package.json."); }
    if (need > 0 && j.components.length === 0) stop("package.json lists " + need + " dependencies, but the SBOM has no components. Run pnpm install and commit the lockfile.");
    sortComponents(j.components);
    if (Array.isArray(j.dependencies)) {
      j.dependencies.sort(byRef);
      for (const d of j.dependencies) if (Array.isArray(d.dependsOn)) d.dependsOn.sort();
    }
    fs.writeFileSync(process.argv[2], JSON.stringify(j, null, 2) + "\n");
  ' "$1" "$2" 2> "$tmp/node.err"
  rc=$?
  if [ "$rc" -eq 3 ]; then
    fail "$(head -n 2 "$tmp/node.err" | tr '\n' ' ')"
  elif [ "$rc" -ne 0 ]; then
    die "node could not read the SBOM: $(head -n 2 "$tmp/node.err" | tr '\n' ' ')"
  fi
}

# Writes the SBOM of a pnpm project to $1.
sbom_pnpm() {
  command -v pnpm > /dev/null 2>&1 || die "pnpm is not installed. Install it (corepack enable), then run this again."
  command -v node > /dev/null 2>&1 || die "node is not installed. Install Node.js, then run this again."
  if [ ! -f pnpm-lock.yaml ]; then die "pnpm-lock.yaml is missing. Run pnpm install and commit the lockfile: the SBOM is built from it."; fi
  pnpm sbom --sbom-format cyclonedx --lockfile-only > "$tmp/raw.json" 2> "$tmp/err.txt" || die "pnpm sbom failed: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')Use a pnpm release that has the sbom command (see packageManager in package.json)."
  check_and_sort_pnpm "$tmp/raw.json" "$1"
}

# Refuses a Python environment that git tracks: a committed .venv can carry .pth files or fake package metadata that run or lie inside the gate.
refuse_tracked_env() {
  local d tracked
  for d in .venv "${VIRTUAL_ENV:-}"; do
    if [ -z "$d" ]; then continue; fi
    tracked=$(git ls-files -- "$d" 2> /dev/null) || tracked=''
    tracked=${tracked%%$'\n'*}
    if [ -n "$tracked" ]; then die "the Python environment '$d' is tracked by git ($tracked is committed). Remove it from git (git rm -r --cached $d) and add it to .gitignore; a committed environment cannot be trusted."; fi
  done
}

# Dies unless $1 is a real virtual environment (pyvenv.cfg beside bin/, a regular-file bin/python, sys.prefix differing from sys.base_prefix); the callers already test that bin/python is executable.
require_real_venv() {
  local dir=$1 p=$1/bin/python
  if [ ! -f "$p" ]; then die "'$p' is not a regular file, so '$dir' is not a usable Python environment. Recreate it: uv venv && uv pip install --require-hashes -r requirements.txt"; fi
  if [ ! -f "$dir/pyvenv.cfg" ]; then die "'$dir' has no pyvenv.cfg, so it is not a real virtual environment and its python is not trusted. Recreate it: uv venv && uv pip install --require-hashes -r requirements.txt"; fi
  if ! "$p" -I -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)' > /dev/null 2>&1; then die "'$p' does not run as a virtual environment interpreter (sys.prefix equals sys.base_prefix, or it failed to start). Recreate it: uv venv && uv pip install --require-hashes -r requirements.txt"; fi
}

# Writes the SBOM of a Python project to $1, built from the packages installed in the project environment.
sbom_python() {
  local py='' req='' rc='' env=''
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
    py=$VIRTUAL_ENV/bin/python
    env=$VIRTUAL_ENV
  elif [ -x .venv/bin/python ]; then
    py=.venv/bin/python
    env=.venv
  else
    die "no project Python environment (VIRTUAL_ENV or .venv). Create the environment and install first: uv venv && uv pip install --require-hashes -r requirements.txt"
  fi
  refuse_tracked_env
  require_real_venv "$env"
  if [ -f requirements.txt ]; then req=requirements.txt; fi
  "$py" -I "$helper" sbom "$req" "$1" 2> "$tmp/err.txt"
  rc=$?
  if [ "$rc" -eq 3 ]; then
    fail "$(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
  elif [ "$rc" -ne 0 ]; then
    die "cannot read the installed Python packages: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')"
  fi
  "$py" -I "$helper" check "$1" 2> "$tmp/err.txt"
  rc=$?
  if [ "$rc" -eq 3 ]; then
    fail "$(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
  elif [ "$rc" -ne 0 ]; then
    die "cannot check the Python SBOM: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')"
  fi
}

has_pnpm=0
has_py=0
if [ -f package.json ]; then has_pnpm=1; fi
if [ -f requirements.txt ] || [ -f pyproject.toml ]; then has_py=1; fi
if [ "$has_pnpm" -eq 0 ] && [ "$has_py" -eq 0 ]; then
  die "no package.json, requirements.txt or pyproject.toml here. Run it from the project root."
fi

pnpm_out=$out
py_out=$out
if [ "$has_pnpm" -eq 1 ] && [ "$has_py" -eq 1 ]; then
  pnpm_out="${out%.json}-pnpm.json"
  py_out="${out%.json}-python.json"
fi
rm -f "$out" "${out%.json}-pnpm.json" "${out%.json}-python.json"
mkdir -p "$(dirname "$out")" || die "cannot create $(dirname "$out")"

if [ "$has_pnpm" -eq 1 ]; then sbom_pnpm "$tmp/pnpm.bom.json"; fi
if [ "$has_py" -eq 1 ]; then sbom_python "$tmp/python.bom.json"; fi
if [ "$has_pnpm" -eq 1 ]; then
  mv "$tmp/pnpm.bom.json" "$pnpm_out" || die "cannot write $pnpm_out"
  echo "generate-sbom: wrote $pnpm_out (pnpm, CycloneDX)"
fi
if [ "$has_py" -eq 1 ]; then
  mv "$tmp/python.bom.json" "$py_out" || die "cannot write $py_out"
  echo "generate-sbom: wrote $py_out (python, CycloneDX)"
fi

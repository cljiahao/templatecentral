#!/usr/bin/env bash
# SBOM: writes a CycloneDX JSON bill of materials to dist/sbom/bom.cdx.json (SBOM_OUT overrides the path).
# pnpm projects use `pnpm sbom` on the lockfile (production dependencies). Python projects are built from the project's own environment (VIRTUAL_ENV, else .venv)
# with its interpreter and the installed package metadata, checked against requirements.txt. Nothing is downloaded, uploaded or signed in to.
# A project with both manifests gets two files, <name>-pnpm.json and <name>-python.json, and no <name>.json.
# Components and dependencies are sorted, so two runs on one lockfile differ only in serialNumber and metadata.timestamp.
# Each document is parsed before it is kept: it must be CycloneDX with a components array that is not empty when the lockfile lists dependencies.
# Exit: 0 written, 1 the document does not match the lockfile, 2 it could not be generated.
# Usage: bash scripts/generate-sbom.sh
set -uo pipefail

out=${SBOM_OUT:-dist/sbom/bom.cdx.json}

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
  ' "$1" "$2" 2> "$tmp/node.err" || fail "$(head -n 2 "$tmp/node.err" | tr '\n' ' ')"
}

# Writes the SBOM of a pnpm project to $1.
sbom_pnpm() {
  command -v pnpm > /dev/null 2>&1 || die "pnpm is not installed. Install it (corepack enable), then run this again."
  command -v node > /dev/null 2>&1 || die "node is not installed. Install Node.js, then run this again."
  if [ ! -f pnpm-lock.yaml ]; then die "pnpm-lock.yaml is missing. Run pnpm install and commit the lockfile: the SBOM is built from it."; fi
  pnpm sbom --sbom-format cyclonedx --lockfile-only --prod > "$tmp/raw.json" 2> "$tmp/err.txt" || die "pnpm sbom failed: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')Use a pnpm release that has the sbom command (see packageManager in package.json)."
  check_and_sort_pnpm "$tmp/raw.json" "$1"
}

# Writes the SBOM of a Python project to $1, built from the packages installed in the project environment.
sbom_python() {
  local py='' rc=''
  if [ ! -f requirements.txt ]; then die "requirements.txt is missing. Compile it first: uv pip compile requirements.in --universal --generate-hashes -o requirements.txt"; fi
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
    py=$VIRTUAL_ENV/bin/python
  elif [ -x .venv/bin/python ]; then
    py=.venv/bin/python
  else
    die "no project Python environment (VIRTUAL_ENV or .venv). Create the environment and install first: uv venv && uv pip install --require-hashes -r requirements.txt"
  fi
  "$py" - requirements.txt "$1" << 'PYEOF' 2> "$tmp/err.txt"
import datetime
import importlib.metadata as md
import json
import re
import sys
import uuid

def norm(n):
    return re.sub(r"[-_.]+", "-", n).lower()

def wanted(path):
    try:
        from packaging.markers import Marker
    except ImportError:
        Marker = None
    names = []
    for raw in open(path, encoding="utf-8"):
        if not raw.strip() or raw[0] in " \t#-":
            continue
        m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", raw)
        if not m:
            continue
        marker = raw.split(";", 1)[1].strip().rstrip("\\").strip() if ";" in raw else ""
        if marker and Marker is not None and not Marker(marker).evaluate():
            continue
        names.append(norm(m.group(0)))
    return names

def stop(message):
    sys.stderr.write(message + "\n")
    sys.exit(3)

dists = {}
for d in md.distributions():
    name = d.metadata["Name"]
    if name:
        dists.setdefault(norm(name), d)
names = wanted(sys.argv[1])
missing = sorted({n for n in names if n not in dists})
if missing:
    stop("requirements.txt lists %s, which %s not installed in the project environment. Install first: uv pip install --require-hashes -r requirements.txt" % (", ".join(missing[:5]), "is" if len(missing) == 1 else "are"))

components, dependencies = [], []
for key in sorted(dists):
    d = dists[key]
    ref = "pkg:pypi/%s@%s" % (key, d.version)
    component = {"type": "library", "bom-ref": ref, "name": d.metadata["Name"], "version": d.version, "purl": ref}
    expr = (d.metadata.get("License-Expression") or "").strip()
    if expr:
        component["licenses"] = [{"expression": expr}]
    components.append(component)
    depends = set()
    for r in d.requires or []:
        if ";" in r and "extra" in r.split(";", 1)[1]:
            continue
        m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", r.strip())
        if m and norm(m.group(0)) in dists:
            depends.add("pkg:pypi/%s@%s" % (norm(m.group(0)), dists[norm(m.group(0))].version))
    dependencies.append({"ref": ref, "dependsOn": sorted(depends)})

if names and not components:
    stop("requirements.txt lists packages, but the project environment has none installed.")
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
doc = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.6",
    "serialNumber": "urn:uuid:" + str(uuid.uuid4()),
    "version": 1,
    "metadata": {"timestamp": stamp, "tools": {"components": [{"type": "application", "name": "generate-sbom.sh"}]}},
    "components": components,
    "dependencies": dependencies,
}
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
with open(sys.argv[2], encoding="utf-8") as f:
    back = json.load(f)
if back.get("bomFormat") != "CycloneDX" or not isinstance(back.get("components"), list):
    stop("the SBOM written is not a CycloneDX document.")
PYEOF
  rc=$?
  if [ "$rc" -eq 3 ]; then fail "$(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"; fi
  if [ "$rc" -ne 0 ]; then die "cannot read the installed Python packages: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')"; fi
  "$py" -c 'import json, sys
j = json.load(open(sys.argv[1]))
sys.exit(0 if j.get("bomFormat") == "CycloneDX" and isinstance(j.get("components"), list) else 3)' "$1" 2> "$tmp/err.txt" || fail "the Python SBOM is not valid CycloneDX JSON with a components array."
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

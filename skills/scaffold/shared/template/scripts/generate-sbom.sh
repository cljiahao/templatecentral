#!/usr/bin/env bash
# SBOM: writes a CycloneDX JSON bill of materials from the lockfile to dist/sbom/bom.cdx.json (SBOM_OUT overrides the path).
# pnpm stacks use `pnpm sbom` (lockfile only, production dependencies). Python uses a pinned cyclonedx-bom run through pipx or uvx on the hashed requirements.txt.
# Nothing is uploaded and no account or key is needed. Components and dependencies are sorted, so two runs on one lockfile differ only in serialNumber and metadata.timestamp.
# Usage: bash scripts/generate-sbom.sh
set -uo pipefail

CYCLONEDX_BOM_VERSION="8.0.1"
out=${SBOM_OUT:-dist/sbom/bom.cdx.json}

die() {
  printf 'generate-sbom: %s\n' "$1" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/generate-sbom.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

# Sorts components and dependencies by reference, because pnpm lists them in a different order on each run.
sort_bom() {
  node -e '
    const fs = require("fs");
    const byRef = (a, b) => String(a["bom-ref"] || a.ref).localeCompare(String(b["bom-ref"] || b.ref));
    const sortComponents = (list) => {
      list.sort(byRef);
      for (const c of list) if (Array.isArray(c.components)) sortComponents(c.components);
    };
    const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (Array.isArray(j.components)) sortComponents(j.components);
    if (Array.isArray(j.dependencies)) {
      j.dependencies.sort(byRef);
      for (const d of j.dependencies) if (Array.isArray(d.dependsOn)) d.dependsOn.sort();
    }
    fs.writeFileSync(process.argv[2], JSON.stringify(j, null, 2) + "\n");
  ' "$1" "$2"
}

# Writes the SBOM of a pnpm project to $1.
sbom_pnpm() {
  command -v pnpm > /dev/null 2>&1 || die "pnpm is not installed. Install it (corepack enable), then run this again."
  if [ ! -f pnpm-lock.yaml ]; then die "pnpm-lock.yaml is missing. Run pnpm install and commit the lockfile: the SBOM is built from it."; fi
  pnpm sbom --sbom-format cyclonedx --lockfile-only --prod > "$tmp/raw.json" 2> "$tmp/err.txt" || die "pnpm sbom failed: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')Use a pnpm release that has the sbom command (see packageManager in package.json)."
  sort_bom "$tmp/raw.json" "$1" || die "cannot read the SBOM pnpm wrote (not valid JSON)."
}

# Writes the SBOM of a Python project to $1.
sbom_python() {
  if [ ! -f requirements.txt ]; then die "requirements.txt is missing. Compile it first: uv pip compile requirements.in --universal --generate-hashes -o requirements.txt"; fi
  if command -v pipx > /dev/null 2>&1; then
    pipx run --spec "cyclonedx-bom==${CYCLONEDX_BOM_VERSION}" cyclonedx-py requirements requirements.txt --of JSON --sv 1.6 -o "$1" > /dev/null 2> "$tmp/err.txt" || die "cyclonedx-py failed: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')"
  elif command -v uvx > /dev/null 2>&1; then
    uvx --from "cyclonedx-bom==${CYCLONEDX_BOM_VERSION}" cyclonedx-py requirements requirements.txt --of JSON --sv 1.6 -o "$1" > /dev/null 2> "$tmp/err.txt" || die "cyclonedx-py failed: $(head -n 3 "$tmp/err.txt" | tr '\n' ' ')"
  else
    die "neither pipx nor uvx is installed, so cyclonedx-bom ${CYCLONEDX_BOM_VERSION} cannot run. Install one of them (pip install pipx, or install uv)."
  fi
}

if [ -f package.json ]; then
  stack=pnpm
  gen=sbom_pnpm
elif [ -f requirements.txt ] || [ -f pyproject.toml ]; then
  stack=python
  gen=sbom_python
else
  die "no package.json, requirements.txt or pyproject.toml here. Run it from the project root."
fi

rm -f "$out"
mkdir -p "$(dirname "$out")" || die "cannot create $(dirname "$out")"
$gen "$tmp/bom.json"
if [ ! -s "$tmp/bom.json" ] || ! grep -qE '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"' "$tmp/bom.json"; then
  die "the generator wrote no CycloneDX document ($stack). Check the lockfile and the tool output above."
fi
mv "$tmp/bom.json" "$out" || die "cannot write $out"
echo "generate-sbom: wrote $out ($stack, CycloneDX)"

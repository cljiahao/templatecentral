#!/usr/bin/env bash
# Licence gate: every installed dependency must carry a licence listed in .claude/allowed-licences.txt.
# Reads the installed packages only (pnpm licenses list for TypeScript stacks, installed package metadata for Python): no account, no key, no hosted service.
# Needs dependencies installed first. Scope: runtime dependencies for pnpm (LICENCES_SCOPE=all adds dev tooling); every installed package for Python.
# Usage: bash scripts/check-licences.sh        Env: ALLOWED_LICENCES_FILE overrides the list path.
set -uo pipefail

allow=${ALLOWED_LICENCES_FILE:-.claude/allowed-licences.txt}
scope=${LICENCES_SCOPE:-prod}

die() {
  printf 'check-licences: %s\n' "$1" >&2
  exit 2
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-licences.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

# Prints "name@version<TAB>licence" for each installed package of a pnpm project.
list_pnpm() {
  case "$scope" in
    all | prod) ;;
    *) die "LICENCES_SCOPE must be prod or all (got '$scope')" ;;
  esac
  command -v pnpm > /dev/null 2>&1 || die "pnpm is not installed. Install it (corepack enable) and run pnpm install first."
  command -v node > /dev/null 2>&1 || die "node is not installed."
  if [ "$scope" = all ]; then
    pnpm licenses list --json > "$tmp/pnpm.json" 2> "$tmp/pnpm.err" || die "pnpm licenses list failed: $(head -n 3 "$tmp/pnpm.err" | tr '\n' ' ')Run pnpm install first."
  else
    pnpm licenses list --json --prod > "$tmp/pnpm.json" 2> "$tmp/pnpm.err" || die "pnpm licenses list failed: $(head -n 3 "$tmp/pnpm.err" | tr '\n' ' ')Run pnpm install first."
  fi
  node -e '
    let s = "";
    process.stdin.on("data", (d) => { s += d; }).on("end", () => {
      const j = JSON.parse(s || "{}");
      for (const [lic, pkgs] of Object.entries(j)) {
        for (const p of pkgs) console.log(p.name + "@" + (p.versions || []).join(",") + "\t" + lic);
      }
    });
  ' < "$tmp/pnpm.json" || die "cannot read the pnpm licence report"
}

# Prints "name@version<TAB>licence" for each package installed in the project's Python environment.
list_python() {
  local py=python3
  if [ -x .venv/bin/python ]; then py=.venv/bin/python; fi
  command -v "$py" > /dev/null 2>&1 || die "python3 is not installed."
  "$py" - << 'PYEOF' || die "cannot read installed package metadata. Create the environment and install requirements first."
import importlib.metadata as md

def licence(meta):
    expr = (meta.get("License-Expression") or "").strip()
    if expr:
        return expr
    lic = (meta.get("License") or "").strip()
    if lic and "\n" not in lic and len(lic) <= 100 and lic.upper() != "UNKNOWN":
        return lic
    labels = [c.split("::")[-1].strip() for c in meta.get_all("Classifier") or [] if c.startswith("License ::")]
    labels = [x for x in labels if x not in ("OSI Approved",)]
    return " AND ".join(sorted(set(labels))) if labels else "Unknown"

seen = set()
for d in md.distributions():
    name = d.metadata["Name"]
    if not name:
        continue
    key = (name.lower(), d.version)
    if key in seen:
        continue
    seen.add(key)
    print("%s@%s\t%s" % (name, d.version, licence(d.metadata)))
PYEOF
}

# Reads "name<TAB>licence" lines on stdin; prints one "name<TAB>licence" line per package whose licence is not allowed.
# An expression passes verbatim, or as OR alternatives where one alternative has every AND part allowed.
# A mix of AND and OR inside parentheses only passes verbatim: it is not parsed.
judge() {
  awk -F '\t' -v allow_file="$allow" '
    function norm(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return tolower(s) }
    function part_ok(p) { return (norm(p) in ok) }
    function alt_ok(alt,   n, i, parts) {
      gsub(/[()]/, "", alt)
      n = split(alt, parts, / [Aa][Nn][Dd] /)
      for (i = 1; i <= n; i++) if (!part_ok(parts[i])) return 0
      return 1
    }
    function expr_ok(e,   n, i, alts, flat) {
      if (norm(e) in ok) return 1
      if (e ~ /\(/ && e ~ / [Aa][Nn][Dd] / && e ~ / [Oo][Rr] /) return 0
      flat = e
      gsub(/^[[:space:]]*\(|\)[[:space:]]*$/, "", flat)
      n = split(flat, alts, / [Oo][Rr] /)
      for (i = 1; i <= n; i++) if (alt_ok(alts[i])) return 1
      return 0
    }
    FILENAME == allow_file {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/^#.*$/, "", line)
      line = norm(line)
      if (line != "") ok[line] = 1
      next
    }
    {
      lic = $2
      if (lic == "" || tolower(lic) == "unknown" || tolower(lic) == "unlicensed" || tolower(lic) ~ /^see licen[cs]e in/ || !expr_ok(lic)) print $1 "\t" (lic == "" ? "Unknown" : lic)
    }
  ' "$allow" -
}

if [ ! -f "$allow" ]; then
  die "$allow is missing. Restore it from the scaffold: it lists the licences the project accepts, one per line."
fi
if ! grep -qvE '^[[:space:]]*(#|$)' "$allow"; then
  die "$allow lists no licence, so every dependency would fail. Restore it from the scaffold."
fi

if [ -f package.json ]; then
  stack=pnpm
  list_pnpm > "$tmp/all.tsv" || exit 2
elif [ -f requirements.txt ] || [ -f pyproject.toml ]; then
  stack=python
  list_python > "$tmp/all.tsv" || exit 2
else
  die "no package.json, requirements.txt or pyproject.toml here. Run it from the project root."
fi

total=$(wc -l < "$tmp/all.tsv" | tr -d ' ')
if [ "$total" -eq 0 ]; then
  die "no installed packages found ($stack). Install the dependencies first (pnpm install, or pip install --require-hashes -r requirements.txt)."
fi

judge < "$tmp/all.tsv" | sort -u > "$tmp/bad.tsv"
if [ -s "$tmp/bad.tsv" ]; then
  while IFS="$(printf '\t')" read -r pkg lic; do
    printf 'check-licences: %s has licence %s, which is not in %s. Replace the package, or add the licence to the list after a human decision (legal review).\n' "$pkg" "$lic" "$allow" >&2
  done < "$tmp/bad.tsv"
  exit 1
fi
echo "check-licences: ok ($total packages, $stack)"

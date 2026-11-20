#!/usr/bin/env bash
# Licence gate: every installed dependency must carry a licence listed in .claude/allowed-licences.txt, or an exception for that package in .claude/licence-exceptions.txt.
# Reads the installed packages only (pnpm licenses list for package.json, the project's own Python environment for requirements.txt or pyproject.toml): no account, no key, no hosted service.
# A project with both manifests is checked for both. Dependencies must be installed first: a missing node_modules or Python environment fails, it never passes.
# Python needs the project environment (VIRTUAL_ENV, else .venv) and every package named in requirements.txt must be installed in it.
# LICENCES_SCOPE=prod|all applies to pnpm only (default prod); Python checks every package installed in the environment.
# Strict by design: several Python licence classifiers on one package are joined with AND, so a dual-licensed package that lists two classifiers needs both allowed.
# Exit: 0 ok, 1 a licence is not allowed, 2 the check could not run.
# Usage: bash scripts/check-licences.sh        Env: ALLOWED_LICENCES_FILE, LICENCE_EXCEPTIONS_FILE override the list paths.
set -uo pipefail

allow=${ALLOWED_LICENCES_FILE:-.claude/allowed-licences.txt}
exc=${LICENCE_EXCEPTIONS_FILE:-.claude/licence-exceptions.txt}
scope=${LICENCES_SCOPE:-prod}

die() {
  printf 'check-licences: %s\n' "$1" >&2
  exit 2
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-licences.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

# Prints "name@version<TAB>licence" for each installed package of a pnpm project.
list_pnpm() {
  command -v pnpm > /dev/null 2>&1 || die "pnpm is not installed. Install it (corepack enable) and run pnpm install first."
  command -v node > /dev/null 2>&1 || die "node is not installed. Install Node.js, then run this again."
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
  local py='' req=''
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
    py=$VIRTUAL_ENV/bin/python
  elif [ -x .venv/bin/python ]; then
    py=.venv/bin/python
  else
    die "no project Python environment (VIRTUAL_ENV or .venv). Create the environment and install first: uv venv && uv pip install --require-hashes -r requirements.txt"
  fi
  if [ -f requirements.txt ]; then req=requirements.txt; fi
  "$py" - "$req" "$tmp/py.note" << 'PYEOF' 2> "$tmp/py.err" || die "cannot read the installed Python packages: $(head -n 3 "$tmp/py.err" | tr '\n' ' ')Create the environment and install first: uv venv && uv pip install --require-hashes -r requirements.txt"
import importlib.metadata as md
import re
import sys

def norm(n):
    return re.sub(r"[-_.]+", "-", n).lower()

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

def wanted(path):
    try:
        from packaging.markers import Marker
    except ImportError:
        Marker = None
    names, unchecked = [], 0
    for raw in open(path, encoding="utf-8"):
        if not raw.strip() or raw[0] in " \t#-":
            continue
        m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", raw)
        if not m:
            continue
        marker = raw.split(";", 1)[1].strip().rstrip("\\").strip() if ";" in raw else ""
        if marker:
            if Marker is None:
                unchecked += 1
                continue
            if not Marker(marker).evaluate():
                continue
        names.append(norm(m.group(0)))
    return names, unchecked

seen = {}
for d in md.distributions():
    name = d.metadata["Name"]
    if name:
        seen.setdefault((norm(name), d.version), (name, licence(d.metadata)))
for (key, version), (name, lic) in sorted(seen.items()):
    print("%s@%s\t%s" % (name, version, lic))

if sys.argv[1]:
    names, unchecked = wanted(sys.argv[1])
    installed = {k for (k, _v) in seen}
    missing = sorted({n for n in names if n not in installed})
    if missing:
        sys.exit("%s lists %s, which %s not installed. " % (sys.argv[1], ", ".join(missing[:5]), "is" if len(missing) == 1 else "are"))
    if unchecked:
        open(sys.argv[2], "w").write("%d requirement lines with markers were not checked (the packaging module is not installed)" % unchecked)
PYEOF
}

# Reads the data file; prints "name<TAB>licence" for each package whose licence is not allowed, then one sentinel line "__judged__<TAB>count".
# An expression passes verbatim, or as OR alternatives where one alternative has every AND part allowed.
# A mix of AND and OR inside parentheses only passes verbatim: it is not parsed.
# A package whose name matches a pattern in the exceptions file may also use that exception's licence.
judge() {
  awk -F '\t' -v allow_file="$allow" -v exc_file="$exc" -v data_file="$1" '
    function norm(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return tolower(s) }
    function glob2re(g,   i, c, r) {
      r = "^"
      for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*") r = r ".*"
        else if (index("\\.^$()[]{}|+?/", c) > 0) r = r "\\" c
        else r = r c
      }
      return r "$"
    }
    function part_ok(p) { return ((norm(p) in ok) || (norm(p) in extra)) }
    function alt_ok(alt,   n, i, parts) {
      gsub(/[()]/, "", alt)
      n = split(alt, parts, / [Aa][Nn][Dd] /)
      for (i = 1; i <= n; i++) if (!part_ok(parts[i])) return 0
      return 1
    }
    function expr_ok(e,   n, i, alts, flat) {
      if (part_ok(e)) return 1
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
    FILENAME == exc_file {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/^[[:space:]]*#.*$/, "", line)
      pat = line
      sub(/^[[:space:]]+/, "", pat)
      sub(/[[:space:]].*$/, "", pat)
      elic = line
      sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "", elic)
      if (pat != "" && elic != line) { ne++; exre[ne] = glob2re(pat); exlic[ne] = norm(elic) }
      next
    }
    FILENAME == data_file {
      n++
      name = $1
      sub(/@[^@]*$/, "", name)
      split("", extra)
      for (i = 1; i <= ne; i++) if (name ~ exre[i]) extra[exlic[i]] = 1
      lic = $2
      if (lic == "" || tolower(lic) == "unknown" || tolower(lic) == "unlicensed" || tolower(lic) ~ /^see licen[cs]e in/ || !expr_ok(lic)) print $1 "\t" (lic == "" ? "Unknown" : lic)
    }
    END { print "__judged__\t" n + 0 }
  ' "$allow" "$exc" "$1"
}

case "$scope" in
  all | prod) ;;
  *) die "LICENCES_SCOPE must be prod or all (got '$scope')" ;;
esac
if [ ! -f "$allow" ]; then
  die "$allow is missing. Restore it from the scaffold: it lists the licences the project accepts, one per line."
fi
if ! grep -qvE '^[[:space:]]*(#|$)' "$allow"; then
  die "$allow lists no licence, so every dependency would fail. Restore it from the scaffold."
fi
if [ -f "$exc" ]; then
  cp "$exc" "$tmp/exc.txt" || die "cannot read $exc"
else
  : > "$tmp/exc.txt"
fi
exc=$tmp/exc.txt

: > "$tmp/all.tsv"
stacks=
if [ -f package.json ]; then
  stacks=pnpm
  list_pnpm >> "$tmp/all.tsv" || exit 2
fi
if [ -f requirements.txt ] || [ -f pyproject.toml ]; then
  stacks="${stacks:+$stacks+}python"
  list_python >> "$tmp/all.tsv" || exit 2
fi
if [ -z "$stacks" ]; then
  die "no package.json, requirements.txt or pyproject.toml here. Run it from the project root."
fi

total=$(wc -l < "$tmp/all.tsv" | tr -d ' ')
if [ "$total" -eq 0 ]; then
  die "no installed packages found ($stacks). Install the dependencies first (pnpm install, or uv pip install --require-hashes -r requirements.txt)."
fi

judge "$tmp/all.tsv" > "$tmp/judged.txt" 2> "$tmp/judge.err" || die "the licence check failed to run: $(head -n 2 "$tmp/judge.err" | tr '\n' ' ')"
if [ "$(tail -n 1 "$tmp/judged.txt")" != "$(printf '__judged__\t%s' "$total")" ]; then
  die "the licence check did not look at all $total packages, so it cannot vouch for them."
fi
grep -v '^__judged__' "$tmp/judged.txt" | sort -u > "$tmp/bad.tsv"
sort_status=$?
if [ "$sort_status" -gt 1 ]; then die "cannot sort the licence findings"; fi
if [ -s "$tmp/bad.tsv" ]; then
  while IFS="$(printf '\t')" read -r pkg lic; do
    printf 'check-licences: %s has licence %s, which is not in %s. Replace the package, or add the licence to the list (or one package to %s) after a human decision (legal review).\n' "$pkg" "$lic" "$allow" "${LICENCE_EXCEPTIONS_FILE:-.claude/licence-exceptions.txt}" >&2
  done < "$tmp/bad.tsv"
  exit 1
fi
echo "check-licences: ok ($total packages, $stacks)"
if [ -s "$tmp/py.note" ]; then printf 'check-licences: note: %s\n' "$(cat "$tmp/py.note")"; fi

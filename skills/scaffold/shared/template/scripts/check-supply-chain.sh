#!/usr/bin/env bash
# Supply-chain gate: install hardening, lockfile registry hosts, hashed Python lockfile, Dependabot cooldown.
# Reads config and lockfiles only: no network, no .env. Usage: bash scripts/check-supply-chain.sh
# Install commands checked: pnpm install, pip/uv pip install -r requirements.txt, uv sync. npm and yarn installs are not checked; the project uses pnpm.
set -uo pipefail

bad_count=0
bad() {
  printf 'check-supply-chain: %s\n' "$1" >&2
  bad_count=$((bad_count + 1))
}

cooldown_floor=7
cr=$(printf '\r')
q="[\"']?"

# Top-level scalar of a flat YAML file: prints the value, nothing when the key is absent.
yaml_value() {
  ws_lines "$1" | grep -E "^$2:" | head -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^["'"'"']//; s/["'"'"']$//'
}

# File lines with quotes around a top-level key removed, so a quoted key reads like a plain one.
ws_lines() {
  sed -E "s/^[\"']([A-Za-z]+)[\"'][[:space:]]*:/\1:/" "$1"
}

ci_files=""
for f in .github/workflows/*.yml .github/workflows/*.yaml azure-pipelines.yml azure-pipelines/*.yml Dockerfile; do
  if [ -f "$f" ]; then ci_files="$ci_files $f"; fi
done

subdir_note() {
  local found
  if [ -f package.json ]; then return 0; fi
  found=$(find . -mindepth 2 -maxdepth 3 -name node_modules -prune -o -name package.json -print 2> /dev/null | sed 's|^\./||' | sort | head -n 3 | tr '\n' ' ')
  if [ -n "$found" ]; then
    echo "check-supply-chain: NOTE no package.json at the project root, so the pnpm checks did not run. Found: ${found}Run this script from that directory too."
  fi
}

pnpm_settings() {
  local ws=pnpm-workspace.yaml v
  if [ ! -f package.json ]; then
    subdir_note
    return 0
  fi
  if [ ! -f "$ws" ]; then
    bad "$ws is missing. Restore it from the scaffold: it holds the install-script allow-list and the release-age cooldown."
    return 0
  fi
  if grep -q "$cr" "$ws"; then
    bad "$ws has CRLF line endings, which the checks cannot read. Convert it to LF (dos2unix $ws) and commit the converted file."
    return 0
  fi
  v=$(yaml_value "$ws" minimumReleaseAge)
  v=${v%\"}
  v=${v#\"}
  case "$v" in
    '' | *[!0-9]*) bad "$ws needs 'minimumReleaseAge: <minutes>' (a number). Add 'minimumReleaseAge: 10080' to wait 7 days before installing a new release." ;;
    *) if [ "$v" -lt 1440 ]; then bad "$ws sets minimumReleaseAge to $v minutes; the floor is 1440 (1 day). Restore 'minimumReleaseAge: 10080'."; fi ;;
  esac
  if ws_lines "$ws" | grep -qE '^minimumReleaseAgeExclude:'; then
    bad "$ws sets minimumReleaseAgeExclude, which disables the cooldown for the listed packages. Remove it and wait out the release age, or pin an older release."
  fi
  if ! ws_lines "$ws" | grep -qE '^allowBuilds:'; then
    bad "$ws has no 'allowBuilds:' map. Dependency install scripts stay off unless a package is listed there with true; add 'allowBuilds:' and list only the packages that need a build."
  fi
  if ws_lines "$ws" | grep -qE "^dangerouslyAllowAllBuilds:[[:space:]]*${q}[Tt][Rr][Uu][Ee]"; then
    bad "$ws sets dangerouslyAllowAllBuilds: true, which runs every dependency's install script. Remove it and list only the needed packages under allowBuilds."
  fi
  if ws_lines "$ws" | grep -qE "^strictDepBuilds:[[:space:]]*${q}[Ff][Aa][Ll][Ss][Ee]"; then
    bad "$ws sets strictDepBuilds: false, which hides unreviewed install scripts. Remove it so an unlisted build script fails the install."
  fi
  if ws_lines "$ws" | grep -qE "^ignoreScripts:[[:space:]]*${q}[Ff][Aa][Ll][Ss][Ee]"; then
    bad "$ws sets ignoreScripts: false. Remove it; the allowBuilds map is the only place to allow a build."
  fi
  if [ -f .npmrc ] && grep -qiE '^[[:space:]]*(ignore-scripts[[:space:]]*=[[:space:]]*false|dangerously-allow-all-builds[[:space:]]*=[[:space:]]*true)' .npmrc; then
    bad ".npmrc re-enables dependency install scripts. Remove the line and use allowBuilds in $ws."
  fi
}

# Lockfile and requirements lines that pull from a host other than the public default or .claude/registry-hosts.txt.
registry_hosts() {
  local allow=.claude/registry-hosts.txt f host hosts line
  for f in pnpm-lock.yaml uv.lock requirements*.txt; do
    if [ ! -f "$f" ]; then continue; fi
    hosts=$(
      {
        grep -vE '^[[:space:]]*#' "$f" | grep -oE '[A-Za-z][A-Za-z0-9+.-]*://[^/"'"'"' ,)>]+' | sed -E 's|^[^:]*://||; s|^[^@]*@||; s|:[0-9]+$||'
        grep -vE '^[[:space:]]*#' "$f" | grep -oE 'git@[A-Za-z0-9.-]+:[A-Za-z~._-]' | sed -E 's|^git@||; s|:.$||'
      } | tr '[:upper:]' '[:lower:]' | sort -u
    )
    for host in $hosts; do
      case "$host" in registry.npmjs.org | pypi.org | files.pythonhosted.org) continue ;; esac
      if [ -f "$allow" ] && grep -vE '^[[:space:]]*(#|$)' "$allow" | tr '[:upper:]' '[:lower:]' | grep -qxF -- "$host"; then continue; fi
      line=$(grep -niF -- "$host" "$f" | head -n 1 | cut -d: -f1)
      bad "$f:${line:-1} resolves a package from $host, which is not the default public registry. Remove the dependency, or add '$host' to $allow after review."
    done
  done
}

# requirements.txt is the install lockfile: every entry pinned with == and carrying --hash=sha256 values.
python_hashes() {
  local f=requirements.txt out
  if [ ! -f "$f" ]; then
    if [ -f package.json ]; then return 0; fi
    echo "check-supply-chain: NOTE no $f at the project root, so the hashed-install check did not run. A Python project keeps one: list direct dependencies in requirements.in, then run uv pip compile requirements.in --generate-hashes -o requirements.txt"
    return 0
  fi
  out=$(awk '
    function flush() { if (req != "" && (req !~ /==/ || req !~ /--hash=sha256:/)) print first ": " req; req = "" }
    /^[[:space:]]*(#|$)/ { next }
    req == "" && /^[[:space:]]*-/ { next }
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      cont = (line ~ /\\[[:space:]]*$/)
      sub(/\\[[:space:]]*$/, "", line)
      if (req == "") first = NR
      req = req " " line
      if (!cont) flush()
    }
    END { flush() }
  ' "$f" | cut -c1-100)
  if [ -n "$out" ]; then
    printf '%s\n' "$out" | while IFS= read -r l; do printf 'check-supply-chain: %s line %s\n' "$f" "$l" >&2; done
    bad "$f has entries without == or --hash=sha256 values. List the direct dependencies in requirements.in (create it if missing), then regenerate: uv pip compile requirements.in --generate-hashes -o requirements.txt"
  fi
}

# CI and Docker installs must be frozen: pnpm --frozen-lockfile, pip --require-hashes, uv --locked or --frozen.
# Each command is judged on its own, so 'A && B' with only B frozen still fails A.
frozen_installs() {
  local f out
  for f in $ci_files; do
    out=$(awk '
      function words(s,   n, i, r) { gsub(/["'"'"']/, "", s); return split(s, tok, /[[:space:]]+/) }
      function has(flag,   i) { for (i = 1; i <= nt; i++) if (tok[i] == flag || tok[i] == flag "=true") return 1; return 0 }
      function pnpm_install(   i) {
        for (i = 1; i <= nt; i++) if (tok[i] == "pnpm") break
        if (i > nt) return 0
        i++
        while (i <= nt && tok[i] ~ /^-/) {
          if (tok[i] == "--dir" || tok[i] == "-C" || tok[i] == "--filter" || tok[i] == "-F" || tok[i] == "--reporter") i++
          i++
        }
        return (tok[i] == "install" || tok[i] == "i")
      }
      function req_file(   i, v) {
        for (i = 1; i <= nt; i++) {
          v = ""
          if (tok[i] == "-r" || tok[i] == "--requirement") v = tok[i + 1]
          else if (tok[i] ~ /^--requirement=/) { v = tok[i]; sub(/^--requirement=/, "", v) }
          else if (tok[i] ~ /^-r./ && tok[i] !~ /^--/) { v = tok[i]; sub(/^-r/, "", v) }
          if (v != "") { sub(/^.*\//, "", v); if (v == "requirements.txt") return 1 }
        }
        return 0
      }
      function check(seg, ln) {
        nt = words(seg)
        if (nt == 0) return
        if (pnpm_install() && !has("--frozen-lockfile")) print ln ": pnpm install without --frozen-lockfile. Add --frozen-lockfile so CI fails when pnpm-lock.yaml is out of date."
        if (seg ~ /(^|[[:space:]\/])(pip[0-9.]*|uv[[:space:]]+pip)[[:space:]]+install/ && req_file() && !has("--require-hashes")) print ln ": installs requirements.txt without --require-hashes. Use pip install --require-hashes -r requirements.txt and install dev requirements in a second command."
        if (seg ~ /(^|[[:space:]\/])uv[[:space:]]+sync/ && !has("--frozen") && !has("--locked")) print ln ": uv sync without --frozen or --locked. Add --locked so CI fails when uv.lock is out of date."
      }
      {
        line = $0
        sub(/\r$/, "", line)
        if (joined == "") start = NR
        if (line ~ /^[[:space:]]*#/ && joined == "") next
        if (line ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, " ", line); joined = joined line; next }
        line = joined line; joined = ""
        n = split(line, segs, /&&|\|\||;|\|/)
        for (s = 1; s <= n; s++) check(segs[s], start)
      }
    ' "$f")
    if [ -n "$out" ]; then
      printf '%s\n' "$out" | while IFS= read -r l; do printf 'check-supply-chain: %s:%s\n' "$f" "$l" >&2; done
      bad_count=$((bad_count + $(printf '%s\n' "$out" | wc -l | tr -d ' ')))
    fi
  done
}

# Dependabot: every ecosystem entry carries a cooldown of at least the seeded 7 days, so a fresh release waits before it is proposed.
dependabot_cooldown() {
  local f=.github/dependabot.yml out
  if [ ! -f "$f" ]; then return 0; fi
  out=$(awk -v floor="$cooldown_floor" '
    function close_entry() {
      if (!inentry) return
      if (days < 0) print ent ": ecosystem entry has no cooldown default-days. Add cooldown: { default-days: " floor " }."
      else if (days + 0 < floor) print ent ": cooldown default-days is " days ", below the floor of " floor ". Set default-days: " floor " or higher."
      inentry = 0
    }
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*-[[:space:]]+package-ecosystem:/ { close_entry(); inentry = 1; ent = NR; days = -1 }
    inentry && match($0, /default-days:[[:space:]]*[0-9]+/) {
      v = substr($0, RSTART, RLENGTH); sub(/^[^:]*:[[:space:]]*/, "", v); days = v
    }
    END { close_entry() }
  ' "$f")
  if [ -n "$out" ]; then
    printf '%s\n' "$out" | while IFS= read -r l; do printf 'check-supply-chain: %s:%s\n' "$f" "$l" >&2; done
    bad_count=$((bad_count + $(printf '%s\n' "$out" | wc -l | tr -d ' ')))
  fi
}

pnpm_settings
registry_hosts
python_hashes
frozen_installs
dependabot_cooldown

if [ "$bad_count" -ne 0 ]; then exit 1; fi
echo "check-supply-chain: ok"

#!/usr/bin/env bash
# Supply-chain gate: install hardening, lockfile registry hosts, hashed Python lockfile, Dependabot cooldown.
# Reads config and lockfiles only: no network, no .env. Usage: bash scripts/check-supply-chain.sh
set -uo pipefail

bad_count=0
bad() {
  printf 'check-supply-chain: %s\n' "$1" >&2
  bad_count=$((bad_count + 1))
}

# Top-level scalar of a flat YAML file: prints the value, nothing when the key is absent.
yaml_value() {
  grep -E "^$2:" "$1" | head -n 1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^["'"'"']//; s/["'"'"']$//'
}

ci_files=""
for f in .github/workflows/*.yml .github/workflows/*.yaml azure-pipelines.yml azure-pipelines/*.yml Dockerfile; do
  if [ -f "$f" ]; then ci_files="$ci_files $f"; fi
done

pnpm_settings() {
  local ws=pnpm-workspace.yaml v
  if [ ! -f package.json ]; then return 0; fi
  if [ ! -f "$ws" ]; then
    bad "$ws is missing. Restore it from the scaffold: it holds the install-script allow-list and the release-age cooldown."
    return 0
  fi
  v=$(yaml_value "$ws" minimumReleaseAge)
  case "$v" in
    '' | *[!0-9]*) bad "$ws needs 'minimumReleaseAge: <minutes>' (a number). Add 'minimumReleaseAge: 10080' to wait 7 days before installing a new release." ;;
    *) if [ "$v" -lt 1440 ]; then bad "$ws sets minimumReleaseAge to $v minutes; the floor is 1440 (1 day). Restore 'minimumReleaseAge: 10080'."; fi ;;
  esac
  if grep -qE '^minimumReleaseAgeExclude:' "$ws"; then
    bad "$ws sets minimumReleaseAgeExclude, which disables the cooldown for the listed packages. Remove it and wait out the release age, or pin an older release."
  fi
  if ! grep -qE '^allowBuilds:' "$ws"; then
    bad "$ws has no 'allowBuilds:' map. Dependency install scripts stay off unless a package is listed there with true; add 'allowBuilds:' and list only the packages that need a build."
  fi
  if grep -qE '^dangerouslyAllowAllBuilds:[[:space:]]*true' "$ws"; then
    bad "$ws sets dangerouslyAllowAllBuilds: true, which runs every dependency's install script. Remove it and list only the needed packages under allowBuilds."
  fi
  if grep -qE '^strictDepBuilds:[[:space:]]*false' "$ws"; then
    bad "$ws sets strictDepBuilds: false, which hides unreviewed install scripts. Remove it so an unlisted build script fails the install."
  fi
  if grep -qE '^ignoreScripts:[[:space:]]*false' "$ws"; then
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
    hosts=$(grep -vE '^[[:space:]]*#' "$f" | grep -oE '[A-Za-z][A-Za-z0-9+.-]*://[^/"'"'"' ,)>]+' | sed -E 's|^[^:]*://||; s|^[^@]*@||; s|:[0-9]+$||' | tr '[:upper:]' '[:lower:]' | sort -u)
    for host in $hosts; do
      case "$host" in registry.npmjs.org | pypi.org | files.pythonhosted.org) continue ;; esac
      if [ -f "$allow" ] && grep -vE '^[[:space:]]*(#|$)' "$allow" | tr '[:upper:]' '[:lower:]' | grep -qxF -- "$host"; then continue; fi
      line=$(grep -nF -- "$host" "$f" | head -n 1 | cut -d: -f1)
      bad "$f:${line:-1} resolves a package from $host, which is not the default public registry. Remove the dependency, or add '$host' to $allow after review."
    done
  done
}

# requirements.txt is the install lockfile: every entry pinned with == and carrying --hash=sha256 values.
python_hashes() {
  local f=requirements.txt out
  if [ ! -f "$f" ]; then return 0; fi
  out=$(awk '
    function flush() { if (req != "" && (req !~ /==/ || req !~ /--hash=sha256:/)) print first ": " req; req = "" }
    /^[[:space:]]*(#|$)/ { next }
    req == "" && /^[[:space:]]*-/ { next }
    {
      line = $0
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
    bad "$f has entries without == or --hash=sha256 values. Regenerate it: pip freeze > requirements.in && uv pip compile requirements.in --generate-hashes -o requirements.txt"
  fi
}

# CI and Docker installs must be frozen: pnpm --frozen-lockfile, pip --require-hashes, uv --locked or --frozen.
frozen_installs() {
  local f hit
  for f in $ci_files; do
    hit=$(grep -nE '(^|[^[:alnum:]_-])pnpm[[:space:]]+(install|i)([[:space:]]|$)' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v -e '--frozen-lockfile' | head -n 1)
    if [ -n "$hit" ]; then bad "$f:${hit%%:*} runs pnpm install without --frozen-lockfile. Add --frozen-lockfile so CI fails when pnpm-lock.yaml is out of date."; fi
    hit=$(grep -nE 'pip[[:space:]]+install[^|;&]*-r[[:space:]]+requirements\.txt' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v -e '--require-hashes' | head -n 1)
    if [ -n "$hit" ]; then bad "$f:${hit%%:*} installs requirements.txt without --require-hashes. Use 'pip install --require-hashes -r requirements.txt' and install dev requirements in a second command."; fi
    hit=$(grep -nE '(^|[^[:alnum:]_-])uv[[:space:]]+sync' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v -e '--frozen' -e '--locked' | head -n 1)
    if [ -n "$hit" ]; then bad "$f:${hit%%:*} runs uv sync without --frozen or --locked. Add --locked so CI fails when uv.lock is out of date."; fi
  done
}

# Dependabot: every ecosystem entry carries a cooldown so a fresh release waits before it is proposed.
dependabot_cooldown() {
  local f=.github/dependabot.yml entries cooldowns
  if [ ! -f "$f" ]; then return 0; fi
  entries=$(grep -cE '^[[:space:]]*-[[:space:]]+package-ecosystem:' "$f" || true)
  cooldowns=$(grep -cE '^[[:space:]]+cooldown:' "$f" || true)
  if [ "$entries" -ne "$cooldowns" ]; then
    bad "$f has $entries ecosystem entries but $cooldowns cooldown blocks. Add 'cooldown: { default-days: 7 }' to every entry."
  fi
}

pnpm_settings
registry_hosts
python_hashes
frozen_installs
dependabot_cooldown

if [ "$bad_count" -ne 0 ]; then exit 1; fi
echo "check-supply-chain: ok"

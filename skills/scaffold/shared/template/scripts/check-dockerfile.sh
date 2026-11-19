#!/usr/bin/env bash
# Dockerfile lint: base images pinned by digest and never :latest, a non-root final USER, no ADD from a URL.
# The static rules need no network; hadolint also runs when installed (CI installs it in ci-gates.sh).
# Usage: bash scripts/check-dockerfile.sh [Dockerfile ...]   (default: every Dockerfile under the project)
set -uo pipefail

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(find . \( -name node_modules -o -name .git -o -name .venv \) -prune -o -type f \( -name Dockerfile -o -name 'Dockerfile.*' \) -print | sed 's|^\./||' | sort)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "check-dockerfile: no Dockerfile found, nothing to check"
  exit 0
fi

lint_static() {
  awk -v file="$1" '
    function report(msg) { printf "%s:%d: %s\n", file, start, msg; found = 1 }
    function resolve(s,   m, name, rep) {
      while (match(s, /[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?/)) {
        name = substr(s, RSTART, RLENGTH)
        gsub(/[${}]/, "", name)
        rep = (name in args) ? args[name] : "?"
        s = substr(s, 1, RSTART - 1) rep substr(s, RSTART + RLENGTH)
      }
      return s
    }
    function unquote(s) { gsub("^[\"" Q "]|[\"" Q "]$", "", s); return s }
    function from_line(rest,   n, parts, i, img, alias, digest, hex, name, tag, slash) {
      n = split(rest, parts, /[[:space:]]+/)
      img = ""; alias = ""
      for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] ~ /^--/) continue
        if (img == "") { img = parts[i]; continue }
        if (toupper(parts[i]) == "AS" && i < n) { alias = tolower(parts[i + 1]); break }
      }
      stage_user = ""; stage_seen = 1; last_from = start
      if (alias != "") stages[alias] = 1
      if (img == "" ) return
      img = resolve(img)
      if (tolower(img) in stages || img == "scratch") return
      if (img ~ /[?]/) { report("base image " img " has an ARG with no default. Give the ARG a default that includes the @sha256 digest."); return }
      digest = index(img, "@sha256:")
      if (digest == 0) {
        report("base image " img " is not pinned by digest. Pin it as <image>:<tag>@sha256:<64 hex> (docker buildx imagetools inspect <image>:<tag> prints the digest).")
      } else {
        hex = substr(img, digest + 8)
        if (length(hex) != 64 || hex !~ /^[0-9a-f]+$/) report("base image " img " has a malformed digest. It must be @sha256: followed by 64 hex characters.")
        img = substr(img, 1, digest - 1)
      }
      slash = img; sub(/^.*\//, "", slash)
      if (slash !~ /:/) { if (digest == 0) report("base image " img " has no tag, which means :latest. Pin a version tag and a digest."); return }
      tag = slash; sub(/^[^:]*:/, "", tag)
      if (tag == "latest") report("base image " img " uses the :latest tag. Pin a version tag and a digest.")
    }
    BEGIN { stage_seen = 0; Q = sprintf("%c", 39) }
    {
      line = $0
      if (joined == "") start = NR
      if (line ~ /^[[:space:]]*#/ && joined == "") next
      if (line ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, " ", line); joined = joined line; next }
      line = joined line; joined = ""
      sub(/^[[:space:]]+/, "", line)
      if (line == "") next
      n = split(line, w, /[[:space:]]+/)
      op = toupper(w[1])
      rest = line; sub(/^[^[:space:]]+[[:space:]]*/, "", rest)
      if (op == "ARG") {
        if (rest ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { name = rest; sub(/=.*$/, "", name); val = rest; sub(/^[^=]*=/, "", val); args[name] = unquote(val) }
      } else if (op == "FROM") { from_line(rest) }
      else if (op == "USER") { stage_user = resolve(unquote(w[2])) }
      else if (op == "ADD") {
        if (rest ~ /(^|[[:space:]])(https?|ftp):\/\//) report("ADD fetches a URL. Download in a RUN step with a checksum check, or COPY a vendored file.")
      }
    }
    END {
      if (!stage_seen) { start = 1; report("no FROM instruction found.") }
      else {
        start = last_from
        if (stage_user == "") report("the final stage sets no USER, so the container runs as root. Add USER <non-root uid> before CMD.")
        else if (stage_user ~ /^(root|0)([:].*)?$/) report("the final stage runs as USER " stage_user ". Use a non-root uid.")
        else if (stage_user ~ /[?]/) report("the final stage USER " stage_user " uses an ARG with no default. Give it a non-root default.")
      }
      exit found
    }
  ' "$1"
}

hadolint_missing() {
  if [ -n "${CI:-}${TF_BUILD:-}${GITHUB_ACTIONS:-}" ]; then
    echo "check-dockerfile: hadolint is not installed, and CI never skips it. Run it through ci-gates.sh dockerfile, which installs the pinned release." >&2
    return 1
  fi
  echo "WARNING check-dockerfile: hadolint is not installed, so the Dockerfile was only linted by the built-in rules; CI runs hadolint and will fail on what it finds." >&2
  echo "WARNING check-dockerfile: install it with: brew install hadolint   (Linux: https://github.com/hadolint/hadolint/releases)" >&2
  return 0
}

rc=0
for f in "${files[@]}"; do
  if ! out=$(lint_static "$f"); then
    printf '%s\n' "$out" >&2
    rc=1
  fi
done

if command -v hadolint > /dev/null 2>&1; then
  for f in "${files[@]}"; do
    if ! hadolint "$f"; then
      echo "check-dockerfile: hadolint reported findings for $f (above). Fix them; do not add an ignore." >&2
      rc=1
    fi
  done
elif ! hadolint_missing; then
  rc=1
fi

if [ "$rc" -ne 0 ]; then exit 1; fi
echo "check-dockerfile: ok (${#files[@]} files)"

#!/usr/bin/env bash
# CI merge gates shared by GitHub Actions and Azure Pipelines.
# Usage: ci-gates.sh <secrets|changelog|readme|comments|deps> [base-branch]
# An empty base-branch scans full history (secrets) or skips the PR-only gates; deps takes no base branch.
# LABELS: space-separated PR labels; skip-changelog / skip-readme-check / skip-comment-check bypass a gate.
# deps has no label bypass: only .claude/dep-audit-allow.txt, whose entries expire, suppresses an advisory.
set -uo pipefail
gate=${1:-}
branch=${2:-}
branch=${branch#refs/heads/}
base="origin/$branch"

fail() {
  if [ -n "${TF_BUILD:-}" ]; then echo "##vso[task.logissue type=error]$1"; else echo "::error::$1"; fi
  exit 1
}
bypassed() {
  case " ${LABELS:-} " in *" $1 "*) echo "$1 label present — OK"; return 0 ;; esac
  return 1
}
pr_only() {
  [ -n "$branch" ] || { echo "$gate: not a pull request — skipped"; exit 0; }
  git rev-parse --verify -q "$base^{commit}" >/dev/null || fail "$base not found — check out with full history (fetch-depth 0)"
}

case "$gate" in
  secrets)
    GITLEAKS_VERSION="8.30.1"   # bump VERSION and SHA256 together, from the release's gitleaks_<version>_checksums.txt
    GITLEAKS_SHA256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"   # gitleaks_<version>_linux_x64.tar.gz
    if ! command -v gitleaks >/dev/null 2>&1; then
      tmp=$(mktemp -d "${RUNNER_TEMP:-${AGENT_TEMPDIRECTORY:-${TMPDIR:-/tmp}}}/gitleaks.XXXXXX")
      curl -fsSL -o "$tmp/gitleaks.tar.gz" "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" || fail "gitleaks download failed"
      echo "${GITLEAKS_SHA256}  $tmp/gitleaks.tar.gz" | sha256sum -c - || fail "gitleaks checksum mismatch"
      tar -xzf "$tmp/gitleaks.tar.gz" -C "$tmp" gitleaks || fail "gitleaks install failed"
      PATH="$tmp:$PATH"   # no sudo: works on hosted and self-hosted Linux x64 agents
    fi
    if [ -n "$branch" ]; then
      gitleaks git --redact --no-banner --log-opts="$base..HEAD" || fail "gitleaks found secrets in this PR's commits"
    else
      gitleaks git --redact --no-banner || fail "gitleaks found secrets in history"
    fi
    ;;
  changelog)
    pr_only
    changed=$(git diff --name-only "$base"...HEAD) || fail "cannot diff against $base"
    # Here-strings, not pipes: under pipefail, grep -q exiting early would SIGPIPE printf and flip the result.
    if grep -qE '^src/' <<< "$changed" && ! grep -qx 'CHANGELOG.md' <<< "$changed"; then
      bypassed skip-changelog && exit 0
      fail "src/ changed but CHANGELOG.md was not updated. Add an entry or apply the 'skip-changelog' label."
    fi
    ;;
  readme)
    pr_only
    tmp=$(mktemp)
    git diff --name-only "$base"...HEAD > "$tmp" || fail "cannot diff against $base"
    missing=""
    while IFS= read -r f; do
      case "$f" in */README.md|README.md) continue ;; esac
      # documentation-kit.md never writes a README into these folders, so never demand one
      case "$f" in .github/*|.azuredevops/*|azure-pipelines/*|*/azure-pipelines/*|.claude/*|*/.claude/*|secrets/*|*/secrets/*|.secrets/*|*/.secrets/*) continue ;; esac
      d=$(dirname "$f")
      rm_path="README.md"
      [ "$d" != "." ] && rm_path="$d/README.md"
      grep -qxF "$rm_path" "$tmp" || missing="$missing\n  - $d/"
    done < "$tmp"
    rm -f "$tmp"
    missing=$(printf '%b' "$missing" | sort -u)
    if [ -n "$missing" ]; then
      bypassed skip-readme-check && exit 0
      printf '%s\n' "$missing"
      fail "Folders changed without updating their README.md (listed above). Update them or apply the 'skip-readme-check' label."
    fi
    ;;
  comments)
    pr_only
    patterns=".claude/comment-hygiene-patterns.txt"
    [ -f "$patterns" ] || fail "comment-hygiene pattern list missing ($patterns)"
    strict_patterns=$(mktemp)
    head -n 10 "$patterns" > "$strict_patterns"
    nl=$(printf '\nx'); nl=${nl%x}
    flagged=""
    while IFS= read -r -d '' f; do
      case "$f" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py) ;; *) continue ;; esac
      [ -f "$f" ] || continue
      while IFS= read -r content; do
        stripped=$(printf '%s' "$content" | sed -E 's@^[[:space:]]*(#|//|\*|"""|/\*\*?)[[:space:]]?@@')
        if [ -n "$stripped" ] && printf '%s' "$stripped" | grep -qEf "$strict_patterns"; then
          flagged="$flagged$nl  - $f: $stripped"
        fi
      done < <(git diff -U0 "$base"...HEAD -- "$f" | grep '^+' | grep -vE '^\+\+\+' | sed 's/^+//' | grep -E '^[[:space:]]*(#|//|\*|"""|/\*\*?)')
    done < <(git diff -z --name-only "$base"...HEAD)
    rm -f "$strict_patterns"
    if [ -n "$flagged" ]; then
      bypassed skip-comment-check && exit 0
      printf '%s\n' "$flagged"
      fail "Change-narration comments found (listed above). State WHAT the code does now, or apply the 'skip-comment-check' label."
    fi
    ;;
  deps)
    PIP_AUDIT_VERSION="2.10.1"   # pip-audit release run through pipx; bump deliberately, it decides what fails the build
    MAX_EXPIRY_DAYS=180          # an allowlist entry may not silence an advisory for longer than this
    allow=".claude/dep-audit-allow.txt"
    tmp=$(mktemp -d "${RUNNER_TEMP:-${AGENT_TEMPDIRECTORY:-${TMPDIR:-/tmp}}}/deps.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT   # fail() exits, so this also covers every failure path
    need() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found — install it before the deps gate"; }
    # pnpm's own suppression settings would bypass the expiring allowlist, so they are rejected outright.
    # package.json is parsed (any JSON layout, a parse failure fails closed); the YAML files and .npmrc are
    # matched by text. Not detected: the YAML complex-key form (`? audit`), which pnpm does not document.
    # pnpm also reads package.json5 and package.yaml; they are not parsed here, so they fail closed.
    for f in package.json5 package.yaml; do
      [ ! -f "$f" ] || fail "unsupported pnpm manifest format: $f — use package.json"
    done
    if [ -f package.json ]; then
      need node
      rc=0
      node -e '
        let pkg;
        try { pkg = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").replace(/^\uFEFF/, "")); } catch (e) { process.exit(2); }
        const walk = (v) => v !== null && typeof v === "object" &&
          Object.entries(v).some(([k, x]) => k === "ignoreGhsas" || k === "ignoreCves" || walk(x));
        const pnpm = pkg && typeof pkg === "object" ? pkg.pnpm : undefined;
        const native = pnpm !== null && typeof pnpm === "object" && ("audit" in pnpm || "auditConfig" in pnpm);
        process.exit(native || walk(pkg) ? 1 : 0);
      ' package.json || rc=$?
      [ "$rc" -ne 2 ] || fail "package.json is not valid JSON — the deps gate cannot check it for advisory suppressions"
      [ "$rc" -eq 0 ] || fail "advisory suppressions belong in $allow, not package.json"
    fi
    q="[\"']"   # an optionally quoted key: audit, "audit" or 'audit'
    for f in pnpm-workspace.yaml .npmrc; do
      [ -f "$f" ] || continue
      # Flow style (audit: { ignore: [...] }) and block style are both caught; any `ignore` under an audit key fails closed.
      if grep -qE "auditConfig|ignoreGhsas|ignoreCves|(^|[^[:alnum:]_.-])${q}?audit${q}?[[:space:]]*:[[:space:]]*\\{" "$f" \
        || awk -v q="$q" '$0 ~ "^" q "?audit" q "?[[:space:]]*:" { inblock = 1; if ($0 ~ /ignore/) found = 1; next } /^[^[:space:]#]/ { inblock = 0 } inblock && /ignore/ { found = 1 } END { exit !found }' "$f"; then
        fail "advisory suppressions belong in $allow, not $f"
      fi
    done
    # Allowlist lines: <ADVISORY-ID> <YYYY-MM-DD expiry> <reason>. An entry stops suppressing on its expiry date.
    today=$(date -u +%Y-%m-%d)
    latest=$(date -u -d "+$MAX_EXPIRY_DAYS days" +%Y-%m-%d 2>/dev/null || date -u -v"+${MAX_EXPIRY_DAYS}d" +%Y-%m-%d) || fail "cannot compute the expiry horizon"
    : > "$tmp/allowed"
    if [ -f "$allow" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        case "$line" in ''|'#'*) continue ;; esac
        if ! printf '%s\n' "$line" | grep -qiE '^(GHSA-[A-Za-z0-9-]+|CVE-[0-9]{4}-[0-9]+|PYSEC-[0-9]{4}-[0-9]+)[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[^[:space:]]'; then
          echo "malformed allowlist line: $line" >&2
          fail "$allow has a malformed line. Format: <GHSA|CVE|PYSEC id> <YYYY-MM-DD expiry> <reason>"
        fi
        read -r id expiry _ <<< "$line"
        y=${expiry%%-*}; md=${expiry#*-}; m=$((10#${md%%-*})); d=$((10#${md#*-}))
        case $m in 1|3|5|7|8|10|12) dim=31 ;; 4|6|9|11) dim=30 ;; 2) dim=28
          if [ $((10#$y % 4)) -eq 0 ] && { [ $((10#$y % 100)) -ne 0 ] || [ $((10#$y % 400)) -eq 0 ]; }; then dim=29; fi ;; *) dim=0 ;; esac
        if [ "$d" -lt 1 ] || [ "$d" -gt "$dim" ]; then
          echo "malformed allowlist line (not a calendar date): $line" >&2
          fail "$allow has an invalid expiry date: $expiry"
        fi
        if [[ ! "$today" < "$expiry" ]]; then
          echo "expired allowlist entry: $id (expired $expiry)" >&2
          fail "$allow entry for $id expired on $expiry. Fix the dependency or renew the entry with a new date and reason."
        fi
        if [[ "$expiry" > "$latest" ]]; then
          echo "allowlist entry too far out: $id ($expiry)" >&2
          fail "$allow entry for $id has an expiry more than $MAX_EXPIRY_DAYS days out ($expiry). Use a date on or before $latest."
        fi
        printf '%s\n' "$id" | tr '[:lower:]' '[:upper:]' >> "$tmp/allowed"
      done < "$allow"
    fi
    : > "$tmp/found"   # one line per finding: <package>|<severity>|<ids>, or !<package>: not audited (...)
    cat > "$tmp/pa.py" <<'PY'
import json, re, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        report = json.load(fh)
except (OSError, ValueError):
    sys.exit(3)
deps = report.get("dependencies") if isinstance(report, dict) else None
if not isinstance(deps, list):
    sys.exit(3)
if not deps:
    sys.exit(4)
for dep in deps:
    name = str(dep.get("name"))
    if dep.get("skip_reason"):
        print("!" + name + ": not audited (" + re.sub(r"\s+", " ", str(dep.get("skip_reason"))).strip() + ")")
    for vuln in dep.get("vulns") or []:
        ids = [vuln.get("id")] + list(vuln.get("aliases") or [])
        print(name + "|n/a|" + (" ".join(i for i in ids if i) or "unnamed"))
PY
    # One pip-audit run: $1 requirements file, $2 label for messages, remaining arguments are extra pip-audit flags.
    py_audit() {
      local file=$1 label=$2 rc
      shift 2
      # pip-audit reports no severity, so every known vulnerability counts.
      pipx run "pip-audit==${PIP_AUDIT_VERSION}" -r "$file" "$@" --format json --progress-spinner off > "$tmp/report.json" 2> "$tmp/err.txt"
      python3 "$tmp/pa.py" "$tmp/report.json" >> "$tmp/found"; rc=$?
      [ "$rc" -ne 4 ] || fail "dependency audit covered no packages ($label)"
      [ "$rc" -eq 0 ] || { cat "$tmp/err.txt" >&2; fail "dependency audit returned no report (pip-audit, $label)"; }
    }
    reqs=()
    for f in requirements*.txt; do if [ -f "$f" ]; then reqs+=("$f"); fi; done
    audited=0
    if [ -f pnpm-lock.yaml ]; then
      audited=1
      need pnpm
      pnpm audit --json --prod > "$tmp/report.json" 2> "$tmp/err.txt"   # exits non-zero when it finds anything: the report decides
      node - "$tmp/report.json" >> "$tmp/found" <<'JS'
const fs = require("fs");
let report;
try { report = JSON.parse(fs.readFileSync(process.argv[2], "utf8")); } catch { process.exit(3); }
if (!report || typeof report.advisories !== "object" || report.advisories === null) process.exit(3);
const meta = report.metadata || {};
const total = Number.isFinite(meta.totalDependencies) ? meta.totalDependencies
  : ["dependencies", "devDependencies", "optionalDependencies"].reduce((n, k) => n + (Number.isFinite(meta[k]) ? meta[k] : 0), 0);
if (!(total > 0)) process.exit(4);
for (const a of Object.values(report.advisories)) {
  if (a.severity !== "high" && a.severity !== "critical") continue;
  const ids = [a.github_advisory_id, ...(Array.isArray(a.cves) ? a.cves : [])].filter(Boolean);
  console.log((a.module_name || "unknown") + "|" + a.severity + "|" + (ids.length ? ids : ["advisory-" + a.id]).join(" "));
}
JS
      rc=$?
      [ "$rc" -ne 4 ] || fail "dependency audit covered no packages (pnpm audit)"
      [ "$rc" -eq 0 ] || { cat "$tmp/err.txt" >&2; fail "dependency audit returned no report (pnpm audit)"; }
    fi
    if [ -f uv.lock ] || [ "${#reqs[@]}" -gt 0 ]; then
      audited=1
      need pipx
      if [ -f uv.lock ]; then
        need uv
        # --no-emit-project: a packaged project exports itself as "-e .", which pip-audit can only skip.
        uv export --frozen --no-dev --no-emit-project --no-emit-workspace --quiet --format requirements-txt -o "$tmp/req.txt" 2> "$tmp/err.txt" || { cat "$tmp/err.txt" >&2; fail "dependency audit returned no report (uv export)"; }
        # The export is hash-pinned, so pip-audit has nothing to resolve or build.
        py_audit "$tmp/req.txt" uv.lock --no-deps --disable-pip
      fi
      for f in ${reqs[@]+"${reqs[@]}"}; do py_audit "$f" "$f"; done
    fi
    [ "$audited" -eq 1 ] || fail "no lockfile found (pnpm-lock.yaml, uv.lock or requirements*.txt) — nothing to audit"
    blocked=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in "!"*) blocked="$blocked${blocked:+$'\n'}  - ${line#!}"; continue ;; esac
      pkg=${line%%|*}; rest=${line#*|}; sev=${rest%%|*}; ids=${rest#*|}
      covered=0
      for id in $ids; do
        if printf '%s\n' "$id" | tr '[:lower:]' '[:upper:]' | grep -qxFf "$tmp/allowed" -; then covered=1; break; fi
      done
      [ "$covered" -eq 1 ] || blocked="$blocked${blocked:+$'\n'}  - $pkg: $ids ($sev)"
    done < <(sort -u "$tmp/found")
    if [ -n "$blocked" ]; then
      printf '%s\n' "$blocked" >&2
      fail "High/critical advisories or unaudited packages (listed above). Upgrade the dependency, or allowlist an audited advisory in $allow with an expiry date and a reason. Unaudited packages cannot be allowlisted: install the missing audit tool or make the package auditable, or remove it."
    fi
    ;;
  *)
    echo "usage: ci-gates.sh <secrets|changelog|readme|comments|deps> [base-branch]" >&2
    exit 2
    ;;
esac
exit 0

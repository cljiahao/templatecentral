#!/usr/bin/env bash
# CI merge gates for GitHub Actions and Azure Pipelines: ci-gates.sh <secrets|changelog|comments|deps|nosonar|testbudget|ratchet|supplychain|workflows|envexample|dockerfile|workarounds|diffcover|licences|sbom|changesize|bundle|list> [base-branch]
set -uo pipefail
gate=${1:-}
branch=${2:-}
branch=${branch#refs/heads/}
base="origin/$branch"

# Every gate but `list` is timed: this script runs again as a child with TC_GATE_TIMED set (an exported TC_GATE_TIMED turns the recording off), then records name, seconds and exit status through gate-budget.sh. stdin, stdout and stderr pass through.
# Why a background child with job control, not a foreground run: bash defers a trap until its foreground command ends, so a TERM sent to this process alone could not stop the gate, and a plain background job starts with SIGINT ignored, which every grandchild would inherit (a timed run would then survive Ctrl-C that kills an untimed one). `set -m` gives the child its own process group with default signals, so INT behaves as in an untimed run, and this process forwards INT, TERM and HUP to that whole group; the handlers are installed before the launch, and a signal that lands during the launch is forwarded right after it. When the child is gone the row is recorded with the gate's own status, then the signal is raised again with its default action, as an untimed run dies of TERM or HUP at once; INT is raised again only when the gate died of it, because an untimed bash lets a gate that survived INT finish with its own status. The caller sees what an untimed run gives, and a signal sent to this process alone also stops the gate, which an untimed run does not do. A gate that reads the terminal is in a background group and would stop; gates are not interactive.
if [ -z "${TC_GATE_TIMED:-}" ] && [ -n "$gate" ] && [ "$gate" != list ]; then
  t0=$(date +%s)
  got=
  child=
  # Forwards signal $1 to the child's group (to the child alone when job control is off) and remembers it.
  forward() {
    got=$1
    if [ -n "$child" ]; then
      kill -s "$1" -- "-$child" 2>/dev/null || kill -s "$1" "$child" 2>/dev/null
    fi
  }
  trap 'forward INT' INT
  trap 'forward TERM' TERM
  trap 'forward HUP' HUP
  set -m
  TC_GATE_TIMED=1 bash "$0" "$@" <&0 &
  child=$!
  set +m
  if [ -n "$got" ]; then forward "$got"; fi
  wait "$child"
  rc=$?
  while kill -0 "$child" 2>/dev/null; do
    wait "$child"
    rc=$?
  done
  if [ -n "$got" ]; then
    # A wait cut short by a signal reports 128 plus the signal, not the gate's status; ask once more for the real one.
    wait "$child"
    rc=$?
  fi
  budget="$(dirname "$0")/gate-budget.sh"
  if [ ! -f "$budget" ]; then
    echo "gate-budget: $budget is missing; the timing of $gate was not recorded" >&2
  else
    bash "$budget" record "$gate" "$t0" "$(date +%s)" "$rc"
    rec_rc=$?
    if [ "$rec_rc" -ne 0 ]; then echo "gate-budget: recording the timing of $gate failed (status $rec_rc)" >&2; fi
  fi
  reraise=0
  case "$got" in
    TERM | HUP) reraise=1 ;;
    INT) if [ "$rc" -eq 130 ]; then reraise=1; fi ;;
  esac
  if [ "$reraise" -eq 1 ]; then
    trap - INT TERM HUP
    kill -s "$got" "$$"
  fi
  exit "$rc"
fi

fail() {
  if [ -n "${TF_BUILD:-}" ]; then echo "##vso[task.logissue type=error]$1"; else echo "::error::$1"; fi
  exit 1
}
bypassed() {
  case " ${LABELS:-} " in *" $1 "*) echo "$1 label present — OK"; return 0 ;; esac
  return 1
}
# A gate runs only when .claude/gates.txt lists it; `list` prints the listed gates.
gate_listed() {
  local manifest line
  manifest="$(dirname "$0")/gates.txt"
  [ -f "$manifest" ] || fail "$manifest is missing — the gate manifest is the authority for which gates exist"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    if [ "${line%%|*}" = "$1" ]; then return 0; fi
  done < "$manifest"
  return 1
}
# Prints one anchored extended regex for the globs the project's own coverage config leaves out of measurement: the coverage exclude array of the vitest or vite config, or omit of pyproject.toml. Prints nothing when there is none.
coverage_excludes() {
  local f
  for f in vitest.config.ts vitest.config.mts vitest.config.js vitest.config.mjs vite.config.ts vite.config.mts vite.config.js vite.config.mjs pyproject.toml; do
    [ -f "$f" ] || continue
    awk -v toml="$([ "$f" = pyproject.toml ] && echo 1 || echo 0)" '
      function conv(g,   i, n, c, o, d) {
        n = length(g); o = ""; d = 0; i = 1
        while (i <= n) {
          c = substr(g, i, 1)
          if (substr(g, i, 3) == "**/") { o = o "(.*/)?"; i += 3; continue }
          if (substr(g, i, 2) == "**") { o = o ".*"; i += 2; continue }
          if (c == "*") o = o "[^/]*"
          else if (c == "?") o = o "[^/]"
          else if (c == "{") { o = o "("; d++ }
          else if (c == "}") { o = o ")"; d-- }
          else if (c == "," && d > 0) o = o "|"
          else if (c ~ /[.+()^$|\\[\]]/) o = o "\\" c
          else o = o c
          i++
        }
        return o
      }
      { T = T $0 "\n" }
      END {
        gsub(/\/\/[^\n]*/, "", T)
        if (toml) { if (!match(T, /\[tool\.coverage\.run\]/)) exit; T = substr(T, RSTART); if (!match(T, /omit[ \t]*=[ \t]*\[/)) exit }
        else { if (!match(T, /coverage[ \t\n]*:[ \t\n]*\{/)) exit; T = substr(T, RSTART); if (!match(T, /exclude[ \t\n]*:[ \t\n]*\[/)) exit }
        T = substr(T, RSTART + RLENGTH); e = index(T, "]"); T = substr(T, 1, e - 1)
        while (match(T, /"[^"]*"|\047[^\047]*\047/)) {
          g = substr(T, RSTART + 1, RLENGTH - 2); T = substr(T, RSTART + RLENGTH)
          printf "%s\n", conv(g)
        }
      }' "$f"
  done | paste -sd '|' - | sed 's/^\(.\)/^(\1/; s/\(.\)$/\1)$/'
}
pr_only() {
  [ -n "$branch" ] || { echo "$gate: not a pull request — skipped"; exit 0; }
  git rev-parse --verify -q "$base^{commit}" >/dev/null || fail "$base not found — check out with full history (fetch-depth 0)"
}

case "$gate" in
  secrets|changelog|comments|deps|nosonar|testbudget|ratchet|supplychain|workflows|envexample|dockerfile|workarounds|diffcover|licences|sbom|changesize|bundle)
    gate_listed "$gate" || fail "gate '$gate' is not listed in .claude/gates.txt"
    ;;
  list)
    manifest="$(dirname "$0")/gates.txt"
    [ -f "$manifest" ] || fail "$manifest is missing — the gate manifest is the authority for which gates exist"
    listed=$(grep -vE '^[[:space:]]*(#|$)' "$manifest" | cut -d'|' -f1)
    [ -n "$listed" ] || fail "$manifest lists no gate"
    printf '%s\n' "$listed"
    exit 0
    ;;
esac
case "$gate" in
  secrets)
    # Bump version and SHA256 together, from the release's gitleaks_<version>_checksums.txt
    GITLEAKS_VERSION="8.30.1"
    GITLEAKS_SHA256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
    if ! command -v gitleaks >/dev/null 2>&1; then
      tmp=$(mktemp -d "${RUNNER_TEMP:-${AGENT_TEMPDIRECTORY:-${TMPDIR:-/tmp}}}/gitleaks.XXXXXX")
      curl -fsSL -o "$tmp/gitleaks.tar.gz" "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" || fail "gitleaks download failed"
      echo "${GITLEAKS_SHA256}  $tmp/gitleaks.tar.gz" | sha256sum -c - || fail "gitleaks checksum mismatch"
      tar -xzf "$tmp/gitleaks.tar.gz" -C "$tmp" gitleaks || fail "gitleaks install failed"
      # No sudo: works on hosted and self-hosted Linux x64 agents
      PATH="$tmp:$PATH"
    fi
    [ -f scripts/scan-secrets.sh ] || fail "scripts/scan-secrets.sh is missing"
    if [ -n "$branch" ]; then
      bash scripts/scan-secrets.sh git --log-opts="$base..HEAD" || fail "possible secrets in this PR's commits (file, line and rule above). Remove the value, rotate it if it was ever pushed, and read it from the environment."
    else
      bash scripts/scan-secrets.sh git || fail "possible secrets in history (file, line and rule above). Remove the value, rotate it, and read it from the environment."
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
        if [ -n "$stripped" ] && grep -qEf "$strict_patterns" <<< "$stripped"; then
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
  ratchet)
    pr_only
    # A PR may not weaken gate config versus its merge base; the merge-base copy of the checker runs, so a PR cannot rewrite the script that judges it.
    runner=scripts/gate-ratchet.sh
    mbase=$(git merge-base "$base" HEAD) || fail "no merge base with $base — check out with full history (fetch-depth 0)"
    runner_tmp=$(mktemp "${RUNNER_TEMP:-${AGENT_TEMPDIRECTORY:-${TMPDIR:-/tmp}}}/gate-ratchet.XXXXXX") || fail "cannot create a temporary file"
    if git show "$mbase:scripts/gate-ratchet.sh" > "$runner_tmp" 2>/dev/null; then
      runner=$runner_tmp
    else
      if git cat-file -e "$mbase:.claude/gates.txt" 2>/dev/null; then rm -f "$runner_tmp"; fail "the merge base has .claude/gates.txt but no scripts/gate-ratchet.sh, so the checker in this change would judge itself; restore scripts/gate-ratchet.sh at the base"; fi
      [ -f "$runner" ] || fail "scripts/gate-ratchet.sh is missing"
    fi
    findings=$(GATE_RATCHET_REEXEC=1 bash "$runner" "$base" 2>&1)
    rc=$?
    guarded_list=$(bash "$runner" --list-guarded "$mbase"); list_rc=$?
    rm -f "$runner_tmp"
    if [ "$list_rc" -ne 0 ] || [ -z "$guarded_list" ]; then
      fail "gate-ratchet.sh --list-guarded $mbase failed or listed nothing (output above), so the files that enforce the gates are unknown; fix the checker."
    fi
    if printf '%s\n' "$guarded_list" | awk -F'\t' 'NF < 3 { bad = 1 } END { exit !bad }'; then
      fail "gate-ratchet.sh --list-guarded $mbase listed a row with fewer than three fields (a runner older than the enforced column), so the files that enforce the gates are unknown; fix the checker."
    fi
    enforced=$(printf '%s\n' "$guarded_list" | awk -F'\t' '$3 == 1 { print $2 }')
    printf '%s\n' "$findings"
    if [ "$rc" -ne 0 ]; then
      if { printf '%s\n' "$enforced" | sed 's/^/E /'; printf '%s\n' "$findings"; } | awk '/^E / { E[substr($0, 3)] = 1; next } /^(WEAKENED|UNREADABLE) / { p = $0; sub(/^[A-Z]+ /, "", p); for (e in E) if (p == e ":" || substr(p, 1, length(e) + 2) == e ": ") hit = 1 } END { exit !hit }'; then
        fail "the allow-gate-change label cannot waive a change to the files that enforce the gates (listed above); it needs the owner review that branch protection requires."
      fi
      if [ "$rc" -ne 1 ] || grep -q '^UNREADABLE ' <<< "$findings"; then
        fail "the allow-gate-change label cannot waive an unreadable config or a checker failure (output above); fix the cause."
      fi
      if bypassed allow-gate-change; then echo "gate-ratchet: the allow-gate-change label waived every finding printed above"; exit 0; fi
      fail "a gate is weaker than at the base branch, or its config is unreadable (output above). Restore it, or have a maintainer apply the 'allow-gate-change' label after review."
    fi
    ;;
  testbudget)
    # ADR-0001: test code may not outgrow source code; the limit lives in scripts/test-budget.sh.
    [ -f scripts/test-budget.sh ] || fail "scripts/test-budget.sh is missing"
    bash scripts/test-budget.sh || fail "test budget exceeded or unreadable (output above). Consolidate duplicate tests with the test-consolidate skill."
    ;;
  nosonar)
    # Matches a marker inside a comment only, so the ESLint rule that bans the word (terms: ['nosonar']) never trips it.
    if hits=$(git grep -nIiE '(#|//|/[*]|^[[:space:]]*[*]).*NOSONAR' -- '*.py' '*.pyi' '*.ts' '*.tsx' '*.mts' '*.cts' '*.js' '*.jsx' '*.mjs' '*.cjs' ':(exclude,top).claude' ':(exclude,top)eslint.config.*'); then rc=0; else rc=$?; fi
    [ "$rc" -le 1 ] || fail "git grep failed while scanning for NOSONAR markers"
    if [ -n "$hits" ]; then
      printf '%s\n' "$hits" >&2
      fail "NOSONAR markers found (file:line above). Delete the marker and fix the finding it hides; if the rule is wrong for the whole project, change it in config in its own reviewed change."
    fi
    ;;
  deps)
    # pip-audit release run through pipx; bump deliberately, it decides what fails the build
    PIP_AUDIT_VERSION="2.10.1"
    # An allowlist entry may not silence an advisory for longer than this many days
    MAX_EXPIRY_DAYS=180
    allow=".claude/dep-audit-allow.txt"
    tmp=$(mktemp -d "${RUNNER_TEMP:-${AGENT_TEMPDIRECTORY:-${TMPDIR:-/tmp}}}/deps.XXXXXX")
    # fail() exits, so the trap covers every failure path
    trap 'rm -rf "$tmp"' EXIT
    need() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found — install it before the deps gate"; }
    # pnpm's own suppression settings would bypass the expiring allowlist, so they are rejected; unparsed formats fail closed.
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
    # An optionally quoted key: audit, "audit" or 'audit'
    q="[\"']"
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
        if ! grep -qiE '^(GHSA-[A-Za-z0-9-]+|CVE-[0-9]{4}-[0-9]+|PYSEC-[0-9]{4}-[0-9]+)[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[^[:space:]]' <<< "$line"; then
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
    # One line per finding: <package>|<severity>|<ids>, or !<package>: not audited
    : > "$tmp/found"
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
      # Exits non-zero when it finds anything; the report decides
      pnpm audit --json --prod > "$tmp/report.json" 2> "$tmp/err.txt"
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
        id_upper=$(printf '%s' "$id" | tr '[:lower:]' '[:upper:]')
        if grep -qxFf "$tmp/allowed" <<< "$id_upper"; then covered=1; break; fi
      done
      [ "$covered" -eq 1 ] || blocked="$blocked${blocked:+$'\n'}  - $pkg: $ids ($sev)"
    done < <(sort -u "$tmp/found")
    if [ -n "$blocked" ]; then
      printf '%s\n' "$blocked" >&2
      fail "High/critical advisories or unaudited packages (listed above). Upgrade the dependency, or allowlist an audited advisory in $allow with an expiry date and a reason. Unaudited packages cannot be allowlisted: install the missing audit tool or make the package auditable, or remove it."
    fi
    echo "deps: no unallowlisted high or critical advisories, every package audited"
    ;;
  workarounds)
    pr_only
    [ -f scripts/check-workarounds.sh ] || fail "scripts/check-workarounds.sh is missing"
    bash scripts/check-workarounds.sh "$base" || fail "this change silences a tool or removes covering tests (output above). Fix the cause; there is no waiver."
    ;;
  diffcover)
    # The CI step runs diff-cover --fail-under=80 and keeps its output in diff-cover.txt; diff-cover exits 0 when the diff has no covered lines, so this gate turns that into a failure whenever measured source changed. Deleted files, files the coverage config leaves out, and files whose added lines are all blank or comment-only have no lines to cover and are skipped.
    pr_only
    changed=$(git diff --name-only --diff-filter=d "$base"...HEAD) || fail "cannot diff against $base"
    src=$(grep -E '^src/.*[.](py|ts|tsx|js|jsx|mjs|cjs)$' <<< "$changed" | grep -vE '(^|/)(test|tests|__tests__)/|[.](test|spec)[.]|(^|/)test_[^/]*[.]py$|_test[.]py$|[.]d[.]ts$') || src=""
    excl=$(coverage_excludes)
    if [ -n "$excl" ] && [ -n "$src" ]; then src=$(grep -vE "$excl" <<< "$src") || src=""; fi
    code=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if git diff -U0 --no-color --no-ext-diff "$base"...HEAD -- "$f" | awk -v py="$(case "$f" in *.py) echo 1 ;; *) echo 0 ;; esac)" '
        /^@@/ { inbody = 1; next }
        inbody && /^[+]/ {
          t = substr($0, 2); sub(/^[ \t]+/, "", t)
          if (t == "") next
          if (py == 1) { if (t ~ /^#/) next }
          else if (t ~ /^(\/\/|\/\*|\*\/|\*( |$))/) next
          code = 1
        }
        END { exit code ? 0 : 1 }'; then
        code="$code$f
"
      fi
    done <<< "$src"
    src=${code%$'\n'}
    if [ -z "$src" ]; then echo "diffcover: no source file changed that needs coverage (deleted, excluded from coverage, or only comments and blank lines) — skipped"; exit 0; fi
    out=${DIFF_COVER_OUTPUT:-diff-cover.txt}
    [ -f "$out" ] || fail "$out is missing although source changed. The diff-cover step must run first and keep its output there."
    if grep -q "No lines with coverage information" "$out"; then
      fail "source changed but the coverage report has no lines for it ($(printf '%s' "$src" | tr '\n' ' ')). The tests did not run with coverage, or the report is stale; regenerate it. Do not exclude the files."
    fi
    echo "diffcover: the coverage report covers the changed source lines"
    ;;
  supplychain)
    [ -f scripts/check-supply-chain.sh ] || fail "scripts/check-supply-chain.sh is missing"
    bash scripts/check-supply-chain.sh || fail "supply-chain check failed (output above)."
    ;;
  workflows)
    [ -f scripts/check-workflows.sh ] || fail "scripts/check-workflows.sh is missing"
    bash scripts/check-workflows.sh || fail "workflow hardening check failed (output above)."
    ;;
  envexample)
    [ -f scripts/check-env-example.sh ] || fail "scripts/check-env-example.sh is missing"
    bash scripts/check-env-example.sh || fail ".env.example drifted from the variables the code reads (output above)."
    ;;
  dockerfile)
    # Bump version and SHA256 together, from the release's checksums.sha256 (hadolint-linux-x86_64)
    HADOLINT_VERSION="2.15.1"
    HADOLINT_SHA256="c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507"
    [ -f scripts/check-dockerfile.sh ] || fail "scripts/check-dockerfile.sh is missing"
    if ! command -v hadolint >/dev/null 2>&1; then
      if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
        fail "hadolint is not installed and this runner is $(uname -s) $(uname -m); the pinned download is Linux x86_64 only. Install hadolint ${HADOLINT_VERSION} on the runner and run again."
      fi
      command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is missing on this runner, so the hadolint download cannot be verified. Install coreutils, or install hadolint ${HADOLINT_VERSION} on the runner."
      tmp=$(mktemp -d "${RUNNER_TEMP:-${AGENT_TEMPDIRECTORY:-${TMPDIR:-/tmp}}}/hadolint.XXXXXX")
      curl -fsSL -o "$tmp/hadolint" "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-x86_64" || fail "hadolint download failed"
      echo "${HADOLINT_SHA256}  $tmp/hadolint" | sha256sum -c - || fail "hadolint checksum mismatch"
      chmod +x "$tmp/hadolint"
      PATH="$tmp:$PATH"
    fi
    bash scripts/check-dockerfile.sh || fail "Dockerfile check failed (output above)."
    ;;
  licences)
    [ -f scripts/check-licences.sh ] || fail "scripts/check-licences.sh is missing"
    bash scripts/check-licences.sh || fail "licence check failed (output above). Install the dependencies first; change .claude/allowed-licences.txt only after a licence review."
    ;;
  sbom)
    [ -f scripts/generate-sbom.sh ] || fail "scripts/generate-sbom.sh is missing"
    bash scripts/generate-sbom.sh || fail "SBOM generation failed (output above). Install the dependencies first."
    ;;
  changesize)
    pr_only
    [ -f scripts/check-change-size.sh ] || fail "scripts/check-change-size.sh is missing"
    bash scripts/check-change-size.sh "$base" || fail "this change is over the size budget, or could not be measured (output above). Split it into smaller reviewed changes."
    ;;
  bundle)
    [ -f scripts/check-bundle-size.sh ] || fail "scripts/check-bundle-size.sh is missing"
    # Only a project with a Next.js or Vite config emits a browser bundle; any other stack skips the build and the script reports why. The frontend folder is BUNDLE_DIR, else the current one.
    # The build output folders are deleted first, so the gate can only measure what this build wrote; check-bundle-size.sh also refuses a tracked dist or .next.
    bdir=${BUNDLE_DIR:-.}
    rm -rf "$bdir/dist" "$bdir/.next"
    if compgen -G "$bdir/next.config.*" >/dev/null || compgen -G "$bdir/vite.config.*" >/dev/null; then
      (cd "$bdir" && pnpm run build) || fail "the build failed, so the bundle size cannot be measured (output above)."
    fi
    bash scripts/check-bundle-size.sh || fail "bundle size check failed (output above). Lazy-load heavy routes or drop the large dependency; raise .claude/bundle-budget.txt only after a human decision."
    ;;
  *)
    echo "usage: ci-gates.sh <secrets|changelog|comments|deps|nosonar|testbudget|ratchet|supplychain|workflows|envexample|dockerfile|workarounds|diffcover|licences|sbom|changesize|bundle|list> [base-branch]" >&2
    exit 2
    ;;
esac
exit 0

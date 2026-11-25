#!/usr/bin/env bash
# Secret scan wrapper: scan-secrets.sh <gitleaks arguments>, for example "git --pre-commit --staged" or "git --log-opts=a..b".
# gitleaks --redact alone prints only a count; this prints file, line and rule for each finding, never the secret, and says how to fix it.
set -uo pipefail

command -v gitleaks > /dev/null 2>&1 || { echo "scan-secrets: gitleaks is not installed. Install it (brew install gitleaks, or the release binary) and run again." >&2; exit 1; }
wd=$(mktemp -d "${TMPDIR:-/tmp}/scan-secrets.XXXXXX") || { echo "scan-secrets: cannot create a temporary directory" >&2; exit 1; }
trap 'rm -rf "$wd"' EXIT

gitleaks "$@" --redact --no-banner --report-format json --report-path "$wd/report.json" > "$wd/out.txt" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "scan-secrets: no secrets found"
  exit 0
fi

if [ -s "$wd/report.json" ] && grep -q '"RuleID"' "$wd/report.json"; then
  echo "scan-secrets: possible secrets found (values hidden). File:line and rule:" >&2
  awk '
    /"RuleID":/ { rule = $2; gsub(/[",]/, "", rule) }
    /"StartLine":/ { ln = $2; gsub(/,/, "", ln) }
    /"File":/ { f = $0; sub(/^[^:]*:[ ]*"/, "", f); sub(/",?$/, "", f) }
    /"Fingerprint":/ { printf "  %s:%s  %s\n", f, ln, rule }
  ' "$wd/report.json" >&2
  {
    echo "Fix: remove the value from the file and read it from the environment instead (a name in .env.example, the value only in your own untracked .env)."
    echo "If it was ever committed or pushed, treat it as exposed: replace it where it was issued, because deleting the line does not remove it from history."
    echo "If it is a false positive, narrow the rule or path in .gitleaks.toml in its own reviewed change."
  } >&2
  exit 1
fi

cat "$wd/out.txt" >&2
echo "scan-secrets: gitleaks failed (exit $rc) without a report. Fix the error above; the scan did not run." >&2
exit 1

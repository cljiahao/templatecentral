#!/usr/bin/env bash
# Runs the post-edit comment scanner over every template tree and every code fence in the guides; fails on any finding.
set -u
cd "$(dirname "$0")/.."
TS=skills/scaffold/shared/template-ts/.claude/hooks/post-edit-comment-check.sh
PY=skills/scaffold/shared/template-py/.claude/hooks/post-edit-comment-check.sh
export COMMENT_HYGIENE_PATTERNS=skills/scaffold/shared/template/.claude/comment-hygiene-patterns.txt
EXEMPT=scripts/check-template-comments.exempt
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

exempt() {
  [ -f "$EXEMPT" ] || return 1
  grep -v '^$' "$EXEMPT" | grep -qxF -- "$1"
}

scan_file() {
  local f=$1 label=${2:-$1} out
  case "$f" in
    *.py) out=$(bash "$PY" --scan "$f") ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) out=$(bash "$TS" --scan "$f") ;;
    *) return 0 ;;
  esac
  [ -n "$out" ] || return 0
  exempt "$label" && return 0
  printf '%s\n' "$out" | sed "s|^[^:]*:|$label:|"
  printf '%s\n' "$out" | wc -l | tr -d ' ' >>"$work/n"
}

total=0
report() {
  local name=$1 n=0
  [ -s "$work/n" ] && n=$(awk '{s+=$1} END{print s}' "$work/n")
  : >"$work/n"
  printf 'check-template-comments: %-22s %s finding(s)\n' "$name" "$n"
  total=$((total + n))
}
: >"$work/n"

while IFS= read -r f; do scan_file "$f"; done < <(find skills/scaffold -path '*/template*/*' -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' \) -not -path '*/node_modules/*' | sort)
report scaffold-templates

while IFS= read -r f; do scan_file "$f"; done < <(find skills/add -path '*template*/*' -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' \) -not -path '*/node_modules/*' | sort)
report add-templates

python3 - "$work/fences" <<'PYEOF'
import os, re, sys
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
ext = {"ts": "ts", "tsx": "tsx", "typescript": "ts", "js": "js", "javascript": "js", "mjs": "mjs", "py": "py", "python": "py"}
n = 0
for root in ("skills/add", "skills/scaffold"):
    for d, _, files in os.walk(root):
        for fn in sorted(files):
            if not fn.endswith(".md"):
                continue
            p = os.path.join(d, fn)
            lines = open(p, encoding="utf-8").read().split("\n")
            i = 0
            while i < len(lines):
                m = re.match(r"^(\s*)```(\w+)", lines[i])
                if m and m.group(2) in ext:
                    start, i, body = i + 1, i + 1, []
                    while i < len(lines) and not re.match(r"^\s*```\s*$", lines[i]):
                        body.append(lines[i]); i += 1
                    n += 1
                    name = "%05d.%s" % (n, ext[m.group(2)])
                    open(os.path.join(out, name), "w", encoding="utf-8").write("\n".join(body) + "\n")
                    open(os.path.join(out, name + ".src"), "w").write("%s:%d" % (p, start + 1))
                i += 1
PYEOF
for f in "$work"/fences/*.*; do
  case "$f" in *.src) continue ;; esac
  src=$(cat "$f.src")
  out=$(bash "$([ "${f##*.}" = py ] && echo "$PY" || echo "$TS")" --scan "$f")
  [ -n "$out" ] || continue
  base=${src%%:*}; off=${src##*:}
  exempt "$base" && continue
  printf '%s\n' "$out" | while IFS= read -r l; do
    ln=${l#*:}; ln=${ln%%:*}; msg=${l#*:*:}
    printf '%s:%s:%s\n' "$base" "$((off + ln - 1))" "$msg"
  done
  printf '%s\n' "$out" | wc -l | tr -d ' ' >>"$work/n"
done
report guide-fences

[ "$total" -eq 0 ] || { echo "check-template-comments: FAIL ($total finding(s))"; exit 1; }
echo "check-template-comments: ok"

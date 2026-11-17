#!/usr/bin/env bash
# Runs the post-edit comment scanner once per language over every template file and every code fence in the guides; fails on any finding.
# Scope: ts/js/py template sources and guide fences (add, scaffold, migrate, standards, review), plus .yml/.yaml template files.
set -u
cd "$(dirname "$0")/.." || exit 2
TS=skills/scaffold/shared/template-ts/.claude/hooks/post-edit-comment-check.sh
PY=skills/scaffold/shared/template-py/.claude/hooks/post-edit-comment-check.sh
export COMMENT_HYGIENE_PATTERNS=skills/scaffold/shared/template/.claude/comment-hygiene-patterns.txt
export COMMENT_HYGIENE_CAP=1000000
die() { echo "check-template-comments: $*" >&2; exit 2; }
for f in "$TS" "$PY" "$COMMENT_HYGIENE_PATTERNS"; do
  [ -s "$f" ] || die "missing or empty input: $f"
done
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

{
  find skills/scaffold -path '*/template*/*' -type f
  find skills/add skills/migrate -path '*template*/*' -type f
} | grep -E '\.(ts|tsx|js|jsx|mjs|cjs|py|yml|yaml)$' | grep -v '/node_modules/' | sort -u >"$work/files"

nfiles=$(wc -l <"$work/files" | tr -d ' ')
[ "$nfiles" -gt 0 ] || die "no template files found to scan"

python3 - "$work" <<'PYEOF'
import os, re, sys
work = sys.argv[1]
out = os.path.join(work, "fences")
os.makedirs(out, exist_ok=True)
ext = {"ts": "ts", "tsx": "tsx", "typescript": "ts", "js": "js", "javascript": "js", "mjs": "mjs", "py": "py", "python": "py"}
n = 0
with open(os.path.join(work, "files"), "a") as lst, open(os.path.join(work, "fences.map"), "w") as mp:
    for root in ("skills/add", "skills/scaffold", "skills/migrate", "skills/standards", "skills/review"):
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
                        name = os.path.join(out, "%05d.%s" % (n, ext[m.group(2)]))
                        open(name, "w", encoding="utf-8").write("\n".join(body) + "\n")
                        lst.write(name + "\n")
                        mp.write("%s\t%s\t%d\n" % (name, p, start + 1))
                    i += 1
PYEOF

[ -s "$work/fences.map" ] || die "no guide fences found to scan"
nfences=$(wc -l <"$work/fences.map" | tr -d ' ')
printf 'a = 1  # canary\n' >"$work/canary.py"; printf 'a = 1  // canary\n' >"$work/canary.ts"; printf 'a: 1  # canary\n' >"$work/canary.yml"
bash "$TS" --scan "$work/canary.ts" 2>&1 | grep -q 'trailing comment' || die "ts scanner did not flag its canary"
bash "$PY" --scan "$work/canary.py" "$work/canary.yml" 2>&1 | grep -c 'trailing comment' | grep -qx 2 || die "py/yaml scanner did not flag its canary"

grep -E '\.(ts|tsx|js|jsx|mjs|cjs)$' "$work/files" | xargs bash "$TS" --scan >"$work/raw" 2>&1
grep -E '\.(py|yml|yaml)$' "$work/files" | xargs bash "$PY" --scan >>"$work/raw" 2>&1

python3 - "$work" "$nfiles" "$nfences" <<'PYEOF'
import os, sys
work = sys.argv[1]
fence = {}
for l in open(os.path.join(work, "fences.map")):
    name, src, off = l.rstrip("\n").split("\t")
    fence[name] = (src, int(off))
counts = {"scaffold-templates": 0, "add-templates": 0, "migrate-templates": 0, "guide-fences": 0}
exempt = set()
if os.path.exists("scripts/check-template-comments.exempt"):
    for l in open("scripts/check-template-comments.exempt"):
        if l.strip() and not l.startswith("#"):
            exempt.add(l.split(" ", 1)[0])
skipped = 0
used = set()
stale = 0
for l in open(os.path.join(work, "raw"), encoding="utf-8", errors="replace"):
    l = l.rstrip("\n")
    path, sep, rest = l.partition(":")
    ln, _, msg = rest.partition(": ")
    if path in fence:
        src, off = fence[path]
        loc = "%s:%d" % (src, off + int(ln) - 1)
        if loc in exempt:
            used.add(loc)
            skipped += 1
            continue
        print("%s: %s" % (loc, msg))
        counts["guide-fences"] += 1
        continue
    if "%s:%s" % (path, ln) in exempt:
        used.add("%s:%s" % (path, ln))
        skipped += 1
        continue
    print(l)
    counts["add-templates" if path.startswith("skills/add") else "migrate-templates" if path.startswith("skills/migrate") else "scaffold-templates"] += 1
for e in sorted(exempt - used):
    print("%s: stale exemption (no finding on that line): remove it from scripts/check-template-comments.exempt" % e)
    stale += 1
total = sum(counts.values()) + stale
if skipped:
    print("check-template-comments: %d finding(s) exempt (see scripts/check-template-comments.exempt)" % skipped)
for k, v in counts.items():
    print("check-template-comments: %-22s %d finding(s)" % (k, v))
if total:
    print("check-template-comments: FAIL (%d finding(s))" % total)
    sys.exit(1)
print("check-template-comments: ok (%s files, %s fences scanned)" % (sys.argv[2], sys.argv[3]))
PYEOF

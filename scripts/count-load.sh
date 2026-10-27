#!/usr/bin/env bash
# scripts/count-load.sh — measure what one scaffold run loads, per stack.
#
# Usage: bash scripts/count-load.sh [--json] [--base REF]
#   Starts at skills/scaffold/SKILL.md and follows every `cat "<skill-dir>/…"` line
#   it finds in the files it loads. Files under skills/scaffold are the scaffold load;
#   files elsewhere under skills/ (build/test/review/cleanup) are reported as utilities.
#   Sizes are UTF-8 bytes; tokens are bytes/4. --base REF adds the delta against the same walk run on that git ref.
# The counter only reports: exit code is always 0.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JSON=0
BASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1 ;;
    --base) BASE="${2:-}"; shift ;;
    *) echo "count-load: unknown option $1" >&2 ;;
  esac
  shift
done

python3 - "$REPO_ROOT" "$JSON" "$BASE" <<'PY'
import json, os, re, subprocess, sys

root, as_json, base = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
STACKS = ["nextjs", "vite-react", "fastapi", "nestjs"]
CAT = re.compile(r'cat "<skill-dir>/([^"]+)"')
DOCS = "skills/scaffold/shared/documentation-kit.md"


def reader(ref):
    def read(rel):
        if ref:
            r = subprocess.run(["git", "-C", root, "show", f"{ref}:{rel}"], capture_output=True)
            return r.stdout.decode("utf-8") if r.returncode == 0 else None
        try:
            with open(os.path.join(root, rel), encoding="utf-8") as fh:
                return fh.read()
        except OSError:
            return None

    def children(rel):
        if ref:
            r = subprocess.run(["git", "-C", root, "ls-tree", "--name-only", f"{ref}:{rel}"], capture_output=True)
            return sorted(r.stdout.decode("utf-8").split()) if r.returncode == 0 else []
        try:
            return sorted(os.listdir(os.path.join(root, rel)))
        except OSError:
            return []

    read.children = children
    return read


def expand(target):
    """Expand one <a|b> alternation; drop targets that still hold a placeholder."""
    m = re.search(r"<([^<>]*\|[^<>]*)>", target)
    if m:
        return [v for alt in m.group(1).split("|") for v in expand(target[:m.start()] + alt + target[m.end():])]
    return [] if "<" in target else [target]


def walk(read, stack):
    """Return (scaffold files, utility files) in load order, as {path: chars}."""
    scaffold, utilities, queue = {}, {}, ["skills/scaffold/SKILL.md"]
    while queue:
        rel = queue.pop(0)
        if rel in scaffold or rel in utilities:
            continue
        text = read(rel)
        if text is None:
            continue
        (scaffold if rel.startswith("skills/scaffold/") else utilities)[rel] = len(text.encode("utf-8"))
        # A utility resolves <skill-dir> to its own folder; a scaffold file, to skills/scaffold.
        home = os.path.dirname(rel) if rel in utilities else "skills/scaffold"
        for target in CAT.findall(text):
            if rel in utilities and target == "<path>":
                # A utility that routes by operation loads one <operation>/implementation.md.
                queue += [f"{home}/{d}/implementation.md" for d in read.children(home) if "." not in d]
                continue
            for variant in expand(target.replace("<stack>", stack)):
                queue.append(os.path.normpath(os.path.join(home, variant)))
    return scaffold, utilities


def measure(ref):
    read = reader(ref)
    if read("skills/scaffold/SKILL.md") is None:
        print(f"count-load: skills/scaffold/SKILL.md not found at {ref or 'the working tree'}; totals are zero", file=sys.stderr)
    out = {}
    for stack in STACKS:
        scaffold, utilities = walk(read, stack)
        out[stack] = {"scaffold": scaffold, "utilities": utilities}
    return out


def tok(chars):
    return chars / 4


cur = measure("")
old = measure(base) if base else None
result = {}
for stack in STACKS:
    s, u = cur[stack]["scaffold"], cur[stack]["utilities"]
    with_docs = sum(s.values())
    entry = {
        "files": {p: {"bytes": c, "tokens": round(tok(c))} for p, c in s.items()},
        "total_with_docs": round(tok(with_docs)),
        "total_without_docs": round(tok(with_docs - s.get(DOCS, 0))),
        "utilities": {p: {"bytes": c, "tokens": round(tok(c))} for p, c in u.items()},
        "utilities_total": round(tok(sum(u.values()))),
    }
    if old:
        os_ = old[stack]["scaffold"]
        base_total = tok(sum(os_.values()))
        entry["base_total_with_docs"] = round(base_total)
        entry["delta_with_docs"] = round(tok(with_docs) - base_total)
        entry["delta_pct"] = round(100 * (tok(with_docs) - base_total) / base_total, 1) if base_total else None
        entry["files_base"] = {p: round(tok(c)) for p, c in os_.items()}
    result[stack] = entry

if as_json:
    json.dump(result, sys.stdout, indent=2)
    print()
    sys.exit(0)

for stack in STACKS:
    e = result[stack]
    print(f"== {stack}")
    for p, v in e["files"].items():
        line = f"  {p:<52} {v['bytes']:>7} bytes {v['tokens']:>6} tok"
        if old:
            delta = v["tokens"] - e["files_base"].get(p, 0)
            line += f" {delta:>+7} vs {base}"
        print(line)
    print(f"  {'total (with documentation-kit.md)':<52} {'':>7}       {e['total_with_docs']:>6} tok")
    print(f"  {'total (without documentation-kit.md)':<52} {'':>7}       {e['total_without_docs']:>6} tok")
    if old:
        print(f"  {'delta vs ' + base:<52} {'':>7}       {e['delta_with_docs']:>+6} tok ({e['delta_pct']:+.1f}%)")
    for p, v in e["utilities"].items():
        print(f"  utility {p:<44} {v['bytes']:>7} bytes {v['tokens']:>6} tok")
    print(f"  {'utilities total':<52} {'':>7}       {e['utilities_total']:>6} tok")
PY
exit 0

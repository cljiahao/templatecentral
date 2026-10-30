#!/usr/bin/env bash
# scripts/count-load.sh — measure what one scaffold run loads, per stack.
#
# Usage: bash scripts/count-load.sh [--json] [--base REF] [--entry SKILL:NAME[@STACK]]... [--summary SKILL|all]...
#   Starts at skills/scaffold/SKILL.md and follows every `cat "<skill-dir>/…"` line
#   it finds in the files it loads. Files under skills/scaffold are the scaffold load;
#   files elsewhere under skills/ (build/test/review/cleanup) are reported as utilities.
#   Sizes are UTF-8 bytes; tokens are bytes/4. --base REF adds the delta against the same walk run on that git ref.
#
# Other skills. --entry measures one realistic invocation of skills/add, skills/migrate or skills/standards:
#   --entry add:auth/nestjs
#   --entry add:database/typescript/nestjs-kysely
#   --entry migrate:general/phase-4-upgrade
#   --entry migrate:nextjs-backend-extraction/nestjs
#   --entry migrate:portal-frame-ancestors@fastapi
#   --entry standards:code-standards/nextjs
# NAME is the leaf's path under skills/<SKILL>/ without .md. An entry loads, in order: SKILL.md; the
# router, which is <dir>.md for a leaf under <dir>/ or else <dir>/implementation.md; the standards
# shared file (code-standards/comments.md or validation-patterns/patterns.md); the leaf; then every
# `cat "<skill-dir>/…"` target of the leaf and of the skill files it loads. A router's own cat lines are
# not followed (they list every leaf), and an inline cat inside the skill's own folder is not followed
# (it is a pointer, not a load). Targets under skills/add are not followed from other skills. @STACK
# fills <stack> in those cat lines; without it a line that holds <stack> is skipped.
# Files under skills/<SKILL> are the skill load; files elsewhere (build/review, scaffold, .claude/rules)
# are utilities. --base REF adds the delta of the total against the same walk run on that ref.
# --summary SKILL lists every entry of that skill (routers excluded) with its tokens; `all` lists all three.
# Without --entry and --summary the scaffold report above is printed, unchanged.
# The counter only reports: exit code is always 0.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JSON=0
BASE=""
ENTRIES=""
SUMMARIES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1 ;;
    --base) BASE="${2:-}"; shift ;;
    --entry) ENTRIES="$ENTRIES${2:-}"$'\n'; shift ;;
    --summary) SUMMARIES="$SUMMARIES${2:-}"$'\n'; shift ;;
    *) echo "count-load: unknown option $1" >&2 ;;
  esac
  shift
done

python3 - "$REPO_ROOT" "$JSON" "$BASE" "$ENTRIES" "$SUMMARIES" <<'PY'
import json, os, re, subprocess, sys

root, as_json, base = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
entry_specs = [x for x in sys.argv[4].split("\n") if x]
summary_args = [x for x in sys.argv[5].split("\n") if x]
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

SKILLS = ("add", "migrate", "standards")
ALL_STACKS = ("nextjs", "vite-react", "fastapi", "nestjs")
CAT_LINE = re.compile(r'^[ \t]*cat "<skill-dir>/([^"]+)"', re.M)
CAT_ANY = re.compile(r'cat "<skill-dir>/([^"]+)"')
SHARED = {"code-standards": "code-standards/comments.md", "validation-patterns": "validation-patterns/patterns.md"}


def entry_walk(read, skill, name, stack):
    """Return ({path: bytes} under skills/<skill>, {path: bytes} elsewhere), or None when the leaf is missing."""
    home = f"skills/{skill}"
    leaf = f"{home}/{name}.md"
    if read(leaf) is None:
        return None
    parent = os.path.dirname(name)
    start = [f"{home}/SKILL.md"]
    if parent:
        if read(f"{home}/{parent}.md") is not None:
            start.append(f"{home}/{parent}.md")
        elif os.path.basename(name) != "implementation" and read(f"{home}/{parent}/implementation.md") is not None:
            start.append(f"{home}/{parent}/implementation.md")
        shared = SHARED.get(parent)
        if shared and f"{home}/{shared}" != leaf:
            start.append(f"{home}/{shared}")
    inside, outside, queue, seen = {}, {}, [leaf], set()
    for rel in start + [leaf]:
        text = read(rel)
        if text is not None:
            inside[rel] = len(text.encode("utf-8"))
    while queue:
        rel = queue.pop(0)
        if rel in seen:
            continue
        seen.add(rel)
        text = read(rel)
        if text is None:
            continue
        bare = set(CAT_LINE.findall(text))
        for target in CAT_ANY.findall(text):
            for variant in expand(target.replace("<stack>", stack) if stack else target):
                path = os.path.normpath(os.path.join(home, variant))
                if skill != "add" and path.startswith("skills/add/"):
                    continue
                if path.startswith(home + "/"):
                    if target not in bare:
                        continue
                    if path not in inside:
                        body = read(path)
                        if body is not None:
                            inside[path] = len(body.encode("utf-8"))
                            queue.append(path)
                    continue
                body = read(path)
                if body is not None:
                    outside[path] = len(body.encode("utf-8"))
    return inside, outside


def load_key(w):
    return tuple(sorted(w[0])) + ("|",) + tuple(sorted(w[1]))


def entry_list(read, skill):
    """Every leaf of the skill as an entry name, plus one per stack where <stack> changes the load."""
    names = []
    base_dir = os.path.join(root, "skills", skill)
    for dirpath, _dirs, files in os.walk(base_dir):
        for f in files:
            rel = os.path.relpath(os.path.join(dirpath, f), base_dir)
            if rel == "SKILL.md" or not f.endswith(".md") or os.path.isdir(os.path.join(base_dir, rel[:-3])):
                continue
            names.append(rel[:-3])
    out = []
    for stem in sorted(names):
        out.append(stem)
        keys = {load_key(entry_walk(read, skill, stem, ""))}
        for st in ALL_STACKS:
            k = load_key(entry_walk(read, skill, stem, st))
            if k not in keys:
                keys.add(k)
                out.append(f"{stem}@{st}")
    return out


def run_entries():
    cur, old = reader(""), (reader(base) if base else None)
    listing = []
    for arg in summary_args:
        for skill in (SKILLS if arg == "all" else (arg,)):
            if skill not in SKILLS:
                print(f"count-load: unknown skill {skill} for --summary", file=sys.stderr)
                continue
            listing += [f"{skill}:{n}" for n in entry_list(cur, skill)]
    result = {}

    def measure_spec(spec):
        skill, _, rest = spec.partition(":")
        name, _, stack = rest.partition("@")
        if skill not in SKILLS or not name:
            print(f"count-load: bad entry {spec} (want SKILL:NAME[@STACK], SKILL one of {', '.join(SKILLS)})", file=sys.stderr)
            return None
        w = entry_walk(cur, skill, name, stack)
        if w is None:
            print(f"count-load: entry {spec}: skills/{skill}/{name}.md not found", file=sys.stderr)
            return None
        s, u = sum(w[0].values()), sum(w[1].values())
        entry = {
            "files": {p: {"bytes": c, "tokens": round(c / 4)} for p, c in w[0].items()},
            "utilities": {p: {"bytes": c, "tokens": round(c / 4)} for p, c in w[1].items()},
            "skill_tokens": round(s / 4),
            "utilities_tokens": round(u / 4),
            "total_tokens": round((s + u) / 4),
        }
        if old:
            bw = entry_walk(old, skill, name, stack)
            bt = round((sum(bw[0].values()) + sum(bw[1].values())) / 4) if bw else 0
            entry["base_total_tokens"] = bt
            entry["delta_tokens"] = entry["total_tokens"] - bt
        return entry

    for spec in entry_specs + listing:
        e = measure_spec(spec)
        if e is not None:
            result[spec] = e
    if as_json:
        json.dump(result, sys.stdout, indent=2)
        print()
        return
    for spec in entry_specs:
        e = result.get(spec)
        if e is None:
            continue
        print(f"== {spec}")
        for p, v in e["files"].items():
            print(f"  {p:<66} {v['bytes']:>7} bytes {v['tokens']:>6} tok")
        print(f"  {'total (skill files)':<66} {'':>7}       {e['skill_tokens']:>6} tok")
        for p, v in e["utilities"].items():
            print(f"  utility {p:<58} {v['bytes']:>7} bytes {v['tokens']:>6} tok")
        print(f"  {'total (with utilities)':<66} {'':>7}       {e['total_tokens']:>6} tok")
        if old:
            print(f"  {'delta vs ' + base:<66} {'':>7}       {e['delta_tokens']:>+6} tok")
    if listing:
        head = f"{'entry':<64} {'skill':>7} {'utility':>8} {'total':>7}" + (f" {'vs ' + base:>10}" if old else "")
        print(head)
        for spec in listing:
            e = result.get(spec)
            if e is None:
                continue
            line = f"{spec:<64} {e['skill_tokens']:>7} {e['utilities_tokens']:>8} {e['total_tokens']:>7}"
            if old:
                line += f" {e['delta_tokens']:>+10}"
            print(line)
        print(f"{len(listing)} entries (tokens = bytes/4)")


if entry_specs or summary_args:
    run_entries()
    sys.exit(0)


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

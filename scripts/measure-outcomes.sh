#!/usr/bin/env bash
# scripts/measure-outcomes.sh — measures what the stack templates actually generate
# (comments, suppressions, test size, config exclusions, CI parallelism and coverage gate).
# Static only: no installs, no network. One table per stack; exit 1 when a number crosses a
# threshold below, 2 on usage error.
#
# Usage: bash scripts/measure-outcomes.sh [REPO_ROOT]   (default: the repo this script is in)
# Override any threshold from the environment, e.g. MO_MAX_COMMENT_PCT=8 bash scripts/measure-outcomes.sh
#
# Thresholds are set just above today's templates. Tighten them as the work lands:
#   - MO_MAX_COMMENT_PCT / MO_MAX_MULTILINE / MO_MAX_PAREN once the comment policy lands
#   - MO_MAX_TESTS_PER_SRC_FILE once test suites are consolidated
#   - MO_MAX_EXCLUSIONS once config exclusions are trimmed
#   - MO_REQUIRE_PARALLEL=1 once CI templates shard or parallelise tests
set -euo pipefail

MO_MAX_COMMENT_PCT=${MO_MAX_COMMENT_PCT:-25}      # comment lines as % of source+comment lines, per stack
MO_MAX_MULTILINE=${MO_MAX_MULTILINE:-30}            # runs of 2+ consecutive comment lines (and block comments), per stack
MO_MAX_PAREN=${MO_MAX_PAREN:-40}                        # comment lines containing a (parenthetical), per stack
MO_MAX_SUPPRESSIONS=${MO_MAX_SUPPRESSIONS:-3}   # eslint-disable, noqa, type: ignore, ts-expect-error, NOSONAR, coverage pragmas, per stack
MO_MAX_TESTS_PER_SRC_FILE=${MO_MAX_TESTS_PER_SRC_FILE:-100} # test cases per source file (x100 integer, 100 = 1.0)
MO_MAX_EXCLUSIONS=${MO_MAX_EXCLUSIONS:-8}         # lint/coverage/Sonar exclusion entries, per stack
MO_REQUIRE_PARALLEL=${MO_REQUIRE_PARALLEL:-0}                  # 1 = a CI template without sharding/parallel settings fails
MO_REQUIRE_DIFF_COVER=${MO_REQUIRE_DIFF_COVER:-1}              # 1 = a CI template without `diff-cover ... --fail-under=80` fails

ROOT=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
[[ -d "$ROOT/skills/scaffold" ]] || { echo "usage: $0 [REPO_ROOT] — no skills/scaffold under $ROOT" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }

export MO_MAX_COMMENT_PCT MO_MAX_MULTILINE MO_MAX_PAREN MO_MAX_SUPPRESSIONS \
  MO_MAX_TESTS_PER_SRC_FILE MO_MAX_EXCLUSIONS MO_REQUIRE_PARALLEL MO_REQUIRE_DIFF_COVER
exec python3 -I - "$ROOT" <<'PY'
import os, re, sys

root = sys.argv[1]
env = os.environ
LIMITS = {
    "comment %": float(env["MO_MAX_COMMENT_PCT"]),
    "multi-line comments": int(env["MO_MAX_MULTILINE"]),
    "parenthetical comments": int(env["MO_MAX_PAREN"]),
    "suppressions": int(env["MO_MAX_SUPPRESSIONS"]),
    "tests per source file": int(env["MO_MAX_TESTS_PER_SRC_FILE"]) / 100,
    "config exclusions": int(env["MO_MAX_EXCLUSIONS"]),
}
REQUIRE_PARALLEL = env["MO_REQUIRE_PARALLEL"] == "1"
REQUIRE_DIFF_COVER = env["MO_REQUIRE_DIFF_COVER"] == "1"

STACKS = {"fastapi": "py", "nestjs": "ts", "nextjs": "ts", "vite-react": "ts"}
CI_DIRS = {"ts": ["github-ts", "azure-ts"], "py": ["github-py", "azure-py"]}
CODE_EXT = {".ts", ".tsx", ".js", ".mjs", ".cjs", ".py"}
SKIP_DIRS = {"node_modules", ".next", "dist", "__pycache__", "coverage"}
SUPPRESS = re.compile(
    r"eslint-disable|noqa|type:\s*ignore|pyright:\s*ignore|@ts-expect-error|@ts-ignore|@ts-nocheck"
    r"|NOSONAR|pragma:\s*no cover|istanbul ignore|v8 ignore|c8 ignore")
TEST_CASE_TS = re.compile(r"\b(?:it|test)(?:\.each\([^)]*\))?\s*\(")
TEST_CASE_PY = re.compile(r"^\s*(?:async\s+)?def test_", re.M)
SHARD = re.compile(r"--shard|shard:|matrix:|-n\s+auto|-n\s+\d|xdist|maxWorkers|--parallel|strategy:\s*parallel|pytest-split|--splits", re.I)
DIFF_COVER = re.compile(r"diff-cover[^\n]*--fail-under[= ]80\b")


def walk(base):
    for d, dirs, files in os.walk(base):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(files):
            yield os.path.join(d, f)


def is_test(path, base):
    rel = os.path.relpath(path, base).split(os.sep)
    name = rel[-1]
    return (".test." in name or ".spec." in name or name.startswith("test_") or name.endswith("_test.py")
            or any(p in ("test", "tests", "__tests__") for p in rel[:-1]))


def comments_and_code(text, py):
    """Return (comment_lines, code_lines, multiline_runs, paren_comments)."""
    cl = code = runs = paren = 0
    run = 0
    in_block = False
    in_doc = False
    for raw in text.splitlines():
        s = raw.strip()
        if not s:
            continue
        is_c = False
        if py:
            if in_doc:
                is_c = True
                if '"""' in s or "'''" in s:
                    in_doc = False
            elif s.startswith(('"""', "'''")):
                is_c = True
                q = s[:3]
                if s.count(q) < 2:
                    in_doc = True
            elif s.startswith("#") and not s.startswith("#!"):
                is_c = True
        else:
            if in_block:
                is_c = True
                if "*/" in s:
                    in_block = False
            elif s.startswith("/*"):
                is_c = True
                if "*/" not in s:
                    in_block = True
            elif s.startswith("//"):
                is_c = True
        if is_c:
            cl += 1
            run += 1
            if "(" in s and ")" in s:
                paren += 1
        else:
            code += 1
            if run >= 2:
                runs += 1
            run = 0
    if run >= 2:
        runs += 1
    return cl, code, runs, paren


def config_exclusions(base):
    """Count lint/coverage/Sonar exclusion entries in the stack's config files."""
    found = []
    for p in walk(base):
        name = os.path.basename(p)
        rel = os.path.relpath(p, base)
        if rel.startswith("src") or rel.startswith("test"):
            continue
        if name.startswith("sonar-project") or name == "sonar-project.properties":
            for ln in open(p, encoding="utf-8", errors="replace"):
                if re.match(r"\s*sonar\.[\w.]*(exclusions|coverage\.exclusions)\s*=", ln):
                    found.extend(x for x in ln.split("=", 1)[1].split(",") if x.strip())
            continue
        if not re.search(r"(eslint\.config|vitest\.config|vite\.config|pyproject|\.coveragerc|jest\.config)", name):
            continue
        text = open(p, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"(?:ignores|exclude|omit|per-file-ignores|coveragePathIgnorePatterns)\s*[:=]\s*(\[[^\]]*\])", text, re.S):
            found.extend(re.findall(r"""['"]([^'"]+)['"]""", m.group(1)))
        in_pf = False
        for ln in text.splitlines():
            if ln.strip().startswith("[tool.ruff.lint.per-file-ignores]"):
                in_pf = True
                continue
            if in_pf:
                if ln.strip().startswith("["):
                    in_pf = False
                elif "=" in ln:
                    found.append(ln.split("=", 1)[0].strip())
    return found


def measure(stack, kind):
    base = os.path.join(root, "skills", "scaffold", stack, "template")
    m = dict(src_files=0, src_loc=0, test_files=0, tests=0, cl=0, runs=0, paren=0, supp=0)
    for p in walk(base):
        ext = os.path.splitext(p)[1]
        text = open(p, encoding="utf-8", errors="replace").read()
        m["supp"] += len(SUPPRESS.findall(text))
        if ext not in CODE_EXT:
            continue
        py = ext == ".py"
        if is_test(p, base):
            m["test_files"] += 1
            m["tests"] += len((TEST_CASE_PY if py else TEST_CASE_TS).findall(text))
        elif os.path.relpath(p, base).startswith("src" + os.sep):
            m["src_files"] += 1
        cl, code, runs, paren = comments_and_code(text, py)
        m["cl"] += cl
        m["runs"] += runs
        m["paren"] += paren
        if not is_test(p, base):
            m["src_loc"] += code
    excl = config_exclusions(base)
    total = m["cl"] + m["src_loc"]
    pct = 100.0 * m["cl"] / total if total else 0.0
    per_file = m["tests"] / m["src_files"] if m["src_files"] else 0.0
    return m, excl, pct, per_file


def ci_status(kind):
    rows = []
    for d in CI_DIRS[kind]:
        base = os.path.join(root, "skills", "scaffold", "shared", "template-ci", d)
        text = "".join(open(p, encoding="utf-8", errors="replace").read() for p in walk(base)) if os.path.isdir(base) else ""
        rows.append((d, bool(SHARD.search(text)), bool(DIFF_COVER.search(text)), bool(text)))
    return rows


failures = []
for stack, kind in STACKS.items():
    if not os.path.isdir(os.path.join(root, "skills", "scaffold", stack, "template")):
        failures.append(f"{stack}: template directory missing")
        continue
    m, excl, pct, per_file = measure(stack, kind)
    values = {
        "comment %": pct, "multi-line comments": m["runs"], "parenthetical comments": m["paren"],
        "suppressions": m["supp"], "tests per source file": per_file, "config exclusions": len(excl),
    }
    print(f"\n== {stack} ==")
    print(f"  source files {m['src_files']}, source LOC {m['src_loc']}, test files {m['test_files']}, test cases {m['tests']}, comment lines {m['cl']}")
    print(f"  {'metric':<24}{'value':>9}{'limit':>9}  status")
    for k, lim in LIMITS.items():
        v = values[k]
        bad = v > lim
        if bad:
            failures.append(f"{stack}: {k} {v:.2f} > {lim}")
        print(f"  {k:<24}{v:>9.2f}{lim:>9.2f}  {'FAIL' if bad else 'ok'}")
    if excl:
        print(f"  exclusions: {', '.join(excl)}")
    print(f"  {'CI template':<24}{'parallel':>9}{'diff-cover80':>14}")
    for d, par, dc, present in ci_status(kind):
        if not present:
            failures.append(f"{stack}: CI template {d} missing")
        if REQUIRE_PARALLEL and not par:
            failures.append(f"{stack}: CI template {d} has no sharding/parallel setting")
        if REQUIRE_DIFF_COVER and not dc:
            failures.append(f"{stack}: CI template {d} lacks diff-cover --fail-under=80")
        print(f"  {d:<24}{'yes' if par else 'no':>9}{'yes' if dc else 'no':>14}")

print()
if failures:
    print("FAIL: " + "\n      ".join(failures))
    sys.exit(1)
print("OK: all outcome metrics within thresholds")
PY

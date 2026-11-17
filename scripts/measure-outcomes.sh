#!/usr/bin/env bash
# scripts/measure-outcomes.sh — measures what generated code looks like. Static only: no installs,
# no network. Exit 0 within thresholds, 1 when a number crosses one, 2 when the tool itself fails
# (unusable path, crash).
#
# Usage:
#   bash scripts/measure-outcomes.sh                  template mode: the four stack templates under skills/scaffold
#   bash scripts/measure-outcomes.sh PROJECT_DIR      project mode: a generated or migrated project
# Environment: MO_REPO_ROOT points template mode at another checkout (used by the tests);
# every MO_* threshold below can be overridden, e.g. MO_MAX_COMMENT_PCT=8.
#
# WHAT THIS MEASURES (and what it does not)
#   Comments, in .ts/.tsx/.js/.mjs/.cjs/.py files (source, tests and config): whole-line comments,
#   runs of 2+ consecutive comment lines (a blank line ends a run), comment lines holding a
#   (parenthetical), and trailing inline comments (code followed by // or # on the same line, found
#   by a line-based scan that skips quoted text). Suppressions in code files. Source and test LOC,
#   test cases, test:source LOC ratio. Lint/test-runner/coverage/Sonar exclusions. CI sharding and
#   the diff-cover 80% gate.
#   It does NOT measure cognitive complexity, duplication or coverage: the lint configs and CI
#   (SonarQube default gate: complexity 15, duplication 3%, coverage 80% on new code) enforce those.
#
# THRESHOLDS ARE A RATCHET: set just above today's templates so a regression fails. Tighten them as
# the numbers drop; never raise one to make a run pass. Known gap: the FastAPI template carries far
# more comments (about 24%) than the TypeScript stacks (3-8%); the limit is not tuned to it.
#   MO_MAX_COMMENT_PCT, MO_MAX_MULTILINE, MO_MAX_PAREN, MO_MAX_TRAILING: comment noise; tighten once
#     the comment policy lands.
#   MO_MAX_SUPPRESSIONS: eslint-disable, noqa, type: ignore, ts-expect-error, NOSONAR, coverage pragmas.
#   MO_MAX_EXCLUSIONS: lint + test-runner/coverage + Sonar exclusion entries; tighten once config is trimmed.
#   MO_MIN_TEST_RATIO / MO_MAX_TEST_RATIO: test LOC per 100 source LOC, a band, not a cap.
#     Floor: a project with no tests must fail, and 80% coverage on new code needs a real suite.
#     Ceiling: oversized, duplicated suites cost CI time and maintenance; the owner wants fewer,
#     consolidated tests. Tighten the ceiling as suites are consolidated.
#   MO_MIN_TESTS: minimum test cases.
#   MO_REQUIRE_PARALLEL=1: a CI file without sharding/parallel settings fails (off until templates shard).
#   MO_REQUIRE_DIFF_COVER=1: a CI file without `diff-cover ... --fail-under=80` fails.
set -euo pipefail

MO_MAX_COMMENT_PCT=${MO_MAX_COMMENT_PCT:-25}
MO_MAX_MULTILINE=${MO_MAX_MULTILINE:-30}
MO_MAX_PAREN=${MO_MAX_PAREN:-40}
MO_MAX_TRAILING=${MO_MAX_TRAILING:-3}
MO_MAX_SUPPRESSIONS=${MO_MAX_SUPPRESSIONS:-3}
MO_MAX_EXCLUSIONS=${MO_MAX_EXCLUSIONS:-8}
MO_MIN_TEST_RATIO=${MO_MIN_TEST_RATIO:-5}
MO_MAX_TEST_RATIO=${MO_MAX_TEST_RATIO:-35}
MO_MIN_TESTS=${MO_MIN_TESTS:-1}
MO_REQUIRE_PARALLEL=${MO_REQUIRE_PARALLEL:-0}
MO_REQUIRE_DIFF_COVER=${MO_REQUIRE_DIFF_COVER:-1}

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }
if [[ $# -gt 1 ]]; then echo "usage: $0 [PROJECT_DIR]" >&2; exit 2; fi
MODE=templates
TARGET=${MO_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
if [[ $# -eq 1 ]]; then
  MODE=project
  [[ -d "$1" ]] || { echo "measure-outcomes: not a directory: $1" >&2; exit 2; }
  TARGET=$(cd "$1" && pwd)
elif [[ ! -d "$TARGET/skills/scaffold" ]]; then
  echo "measure-outcomes: no skills/scaffold under $TARGET" >&2
  exit 2
fi

export MO_MAX_COMMENT_PCT MO_MAX_MULTILINE MO_MAX_PAREN MO_MAX_TRAILING MO_MAX_SUPPRESSIONS \
  MO_MAX_EXCLUSIONS MO_MIN_TEST_RATIO MO_MAX_TEST_RATIO MO_MIN_TESTS MO_REQUIRE_PARALLEL MO_REQUIRE_DIFF_COVER
exec python3 -I - "$MODE" "$TARGET" <<'PY'
import os, re, subprocess, sys

mode, root = sys.argv[1], sys.argv[2]
env = os.environ
LIMITS = [  # (label, limit, kind)  kind: max or min
    ("comment %", float(env["MO_MAX_COMMENT_PCT"]), "max"),
    ("multi-line comments", int(env["MO_MAX_MULTILINE"]), "max"),
    ("parenthetical comments", int(env["MO_MAX_PAREN"]), "max"),
    ("trailing inline comments", int(env["MO_MAX_TRAILING"]), "max"),
    ("suppressions", int(env["MO_MAX_SUPPRESSIONS"]), "max"),
    ("exclusions (all kinds)", int(env["MO_MAX_EXCLUSIONS"]), "max"),
    ("test cases", int(env["MO_MIN_TESTS"]), "min"),
    ("test LOC per 100 src LOC", int(env["MO_MIN_TEST_RATIO"]), "min"),
    ("test LOC per 100 src LOC", int(env["MO_MAX_TEST_RATIO"]), "max"),
]
REQUIRE_PARALLEL = env["MO_REQUIRE_PARALLEL"] == "1"
REQUIRE_DIFF_COVER = env["MO_REQUIRE_DIFF_COVER"] == "1"

TEMPLATE_STACKS = {"fastapi": "py", "nestjs": "ts", "nextjs": "ts", "vite-react": "ts"}
CI_DIRS = {"ts": ["github-ts", "azure-ts"], "py": ["github-py", "azure-py"]}
CODE_EXT = {".ts", ".tsx", ".js", ".mjs", ".cjs", ".py"}
SKIP_DIRS = {"node_modules", ".next", "dist", "build", "__pycache__", "coverage", ".venv", "venv", ".git", ".turbo"}
SUPPRESS = re.compile(
    r"eslint-disable|noqa|type:\s*ignore|pyright:\s*ignore|@ts-expect-error|@ts-ignore|@ts-nocheck"
    r"|NOSONAR|pragma:\s*no cover|istanbul ignore|v8 ignore|c8 ignore")
TEST_CASE_TS = re.compile(r"(?<![.\w])(?:it|test)(?:\.(?:each|only|skip|concurrent))*\s*(?:\(|`)")
TEST_CASE_PY = re.compile(r"^\s*(?:async\s+)?def test_", re.M)
SHARD = re.compile(r"--shard|shard:|matrix:|-n\s+auto|-n\s+\d|xdist|maxWorkers|--parallel|strategy:\s*parallel|pytest-split|--splits", re.I)
DIFF_COVER = re.compile(r"diff-cover[^\n]*--fail-under[= ]80\b")
SONAR_KEYS = ("sonar.exclusions", "sonar.coverage.exclusions", "sonar.cpd.exclusions")


def list_files(base):
    """Project files, honouring .gitignore inside a git work tree; else a walk without SKIP_DIRS."""
    out = []
    try:
        r = subprocess.run(["git", "-C", base, "ls-files", "-co", "--exclude-standard", "-z"],
                           capture_output=True, check=True)
        names = [n for n in r.stdout.decode("utf-8", "replace").split("\0") if n]
        out = [os.path.join(base, n) for n in names if os.path.isfile(os.path.join(base, n))]
    except (OSError, subprocess.CalledProcessError):
        for d, dirs, files in os.walk(base):
            dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
            out.extend(os.path.join(d, f) for f in sorted(files))
    keep = []
    for p in out:
        if not SKIP_DIRS.intersection(os.path.relpath(p, base).split(os.sep)[:-1]):
            keep.append(p)
    return sorted(keep)


def read(p):
    with open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def comps(path, base):
    return os.path.relpath(path, base).split(os.sep)


def is_test(path, base):
    rel = comps(path, base)
    name = rel[-1]
    return (".test." in name or ".spec." in name or name.startswith("test_") or name.endswith("_test.py")
            or any(p in ("test", "tests", "__tests__") for p in rel[:-1]))


def split_trailing(line, py):
    """Return True when code is followed by a // (ts) or # (py) comment outside quotes."""
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "'\"`":
            quote = c
        elif py and c == "#":
            return line[:i].strip() != ""
        elif not py and c == "/" and line[i + 1:i + 2] == "/":
            return line[:i].strip() != ""
        i += 1
    return False


def scan_comments(text, py):
    """Return (comment_lines, code_lines, multiline_runs, paren_comments, trailing)."""
    cl = code = runs = paren = trailing = 0
    run = 0
    in_block = in_doc = False
    for raw in text.splitlines():
        s = raw.strip()
        if not s:
            if run >= 2:
                runs += 1
            run = 0
            continue
        is_c = False
        if py:
            if in_doc:
                is_c = True
                if '"""' in s or "'''" in s:
                    in_doc = False
            elif s.startswith(('"""', "'''")):
                is_c = True
                if s.count(s[:3]) < 2:
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
            if split_trailing(s, py):
                trailing += 1
    if run >= 2:
        runs += 1
    return cl, code, runs, paren, trailing


def config_entries(base, files):
    """Exclusion entries by kind: lint ignores, test-runner/coverage excludes, Sonar (by key or None)."""
    lint, cov, sonar, sonar_file = [], [], {}, None
    for p in files:
        rel = comps(p, base)
        name = rel[-1]
        if rel[0] in ("src", "test", "tests") and len(rel) > 1:
            continue
        if name == "sonar-project.properties":
            sonar_file = os.path.relpath(p, base)
            text = read(p).replace("\\\n", "")
            for ln in text.splitlines():
                m = re.match(r"\s*(sonar\.[\w.]+)\s*[=:]\s*(.*)", ln)
                if m and m.group(1) in SONAR_KEYS:
                    sonar.setdefault(m.group(1), []).extend(x.strip() for x in m.group(2).split(",") if x.strip())
            continue
        if not re.search(r"(eslint\.config|vitest\.config|vite\.config|pyproject|\.coveragerc|jest\.config|pytest\.ini|setup\.cfg)", name):
            continue
        text = read(p)
        is_lint = "eslint" in name
        for m in re.finditer(r"(ignores|exclude|omit|coveragePathIgnorePatterns)\s*[:=]\s*(\[[^\]]*\])", text, re.S):
            items = re.findall(r"""['"]([^'"]+)['"]""", m.group(2))
            (lint if is_lint and m.group(1) == "ignores" else cov).extend(items)
        cov.extend(re.findall(r"--ignore[= ](\S+)", text))
        in_pf = False
        for ln in text.splitlines():
            if ln.strip().startswith("[tool.ruff") and "per-file-ignores" in ln:
                in_pf = True
            elif in_pf:
                if ln.strip().startswith("["):
                    in_pf = False
                elif "=" in ln:
                    lint.append(ln.split("=", 1)[0].strip().strip('"'))
    return lint, cov, sonar, sonar_file


def detect_stack(d):
    names = set(os.listdir(d)) if os.path.isdir(d) else set()
    pkg = read(os.path.join(d, "package.json")) if "package.json" in names else ""
    py = "".join(read(os.path.join(d, n)) for n in names if n in ("requirements.txt", "pyproject.toml", "requirements-dev.txt"))
    if any(n.startswith("next.config.") for n in names):
        return "nextjs", "ts"
    if "nest-cli.json" in names or "@nestjs/core" in pkg:
        return "nestjs", "ts"
    if any(n.startswith("vite.config.") for n in names):
        return "vite-react", "ts"
    if re.search(r"fastapi", py, re.I):
        return "fastapi", "py"
    return None


def measure(base):
    files = list_files(base)
    m = dict(src_files=0, src_loc=0, test_files=0, test_loc=0, tests=0, cl=0, runs=0, paren=0, trail=0, supp=0)
    code_files = [p for p in files if os.path.splitext(p)[1] in CODE_EXT]
    has_src = any("src" in comps(p, base)[:-1] for p in code_files)
    src_stems, test_stems = set(), []
    for p in code_files:
        py = p.endswith(".py")
        text = read(p)
        m["supp"] += len(SUPPRESS.findall(text))
        cl, code, runs, paren, trail = scan_comments(text, py)
        m["cl"] += cl
        m["runs"] += runs
        m["paren"] += paren
        m["trail"] += trail
        stem = re.sub(r"^test_|_test$|\.(test|spec)$", "", os.path.splitext(os.path.basename(p))[0])
        stem = re.sub(r"\.(test|spec)$", "", stem)
        if is_test(p, base):
            m["test_files"] += 1
            m["test_loc"] += code
            m["tests"] += len((TEST_CASE_PY if py else TEST_CASE_TS).findall(text))
            test_stems.append(stem)
        elif "src" in comps(p, base)[:-1] or not has_src:
            m["src_files"] += 1
            m["src_loc"] += code
            src_stems.add(stem)
    m["orphan_tests"] = sum(1 for s in test_stems if s not in src_stems)
    lint, cov, sonar, sonar_file = config_entries(base, files)
    return m, files, lint, cov, sonar, sonar_file


def ci_rows(base, files, kind, tmpl_root=None):
    rows = []
    if tmpl_root:
        for d in CI_DIRS[kind]:
            tdir = os.path.join(tmpl_root, "skills", "scaffold", "shared", "template-ci", d)
            text = "".join(read(p) for p in list_files(tdir)) if os.path.isdir(tdir) else ""
            rows.append((d, bool(SHARD.search(text)), bool(DIFF_COVER.search(text)), bool(text)))
        return rows
    for p in files:
        rel = os.path.relpath(p, base)
        if re.search(r"(^|/)(\.github/workflows/[^/]+\.ya?ml|azure-pipelines[^/]*\.ya?ml|azure-pipelines/.+\.ya?ml)$", rel):
            text = read(p)
            rows.append((rel, bool(SHARD.search(text)), bool(DIFF_COVER.search(text)), True))
    return rows


def report(label, base, kind, tmpl_root, failures):
    m, files, lint, cov, sonar, sonar_file = measure(base)
    total = m["cl"] + m["src_loc"] + m["test_loc"]
    sonar_n = sum(len(v) for v in sonar.values())
    values = {
        "comment %": 100.0 * m["cl"] / total if total else 0.0,
        "multi-line comments": m["runs"], "parenthetical comments": m["paren"],
        "trailing inline comments": m["trail"], "suppressions": m["supp"],
        "exclusions (all kinds)": len(lint) + len(cov) + sonar_n, "test cases": m["tests"],
        "test LOC per 100 src LOC": 100.0 * m["test_loc"] / m["src_loc"] if m["src_loc"] else 0.0,
    }
    print(f"\n== {label} ==")
    print(f"  source files {m['src_files']}, source LOC {m['src_loc']}, test files {m['test_files']}, "
          f"test LOC {m['test_loc']}, test cases {m['tests']}, comment lines {m['cl']}")
    print(f"  test files with no same-named source file (info only): {m['orphan_tests']}")
    print(f"  {'metric':<27}{'value':>9}{'limit':>10}  status")
    for k, lim, kindl in LIMITS:
        v = values[k]
        bad = v > lim if kindl == "max" else v < lim
        if bad:
            failures.append(f"{label}: {k} {v:.2f} {'>' if kindl == 'max' else '<'} {lim} ({kindl})")
        print(f"  {k:<27}{v:>9.2f}{('<=' if kindl == 'max' else '>=') + str(lim):>10}  {'FAIL' if bad else 'ok'}")
    print(f"  lint ignores {len(lint)}: {', '.join(lint) or '-'}")
    print(f"  vitest/pytest/coverage excludes {len(cov)}: {', '.join(cov) or '-'}")
    if sonar_file:
        print(f"  Sonar ({sonar_file}):")
        for k in SONAR_KEYS:
            print(f"    {k} {len(sonar.get(k, []))}: {', '.join(sonar.get(k, [])) or '-'}")
    else:
        print("  Sonar: no sonar-project.properties found")
    rows = ci_rows(base, files, kind, tmpl_root)
    if not rows:
        print("  CI: no CI files found")
    else:
        print(f"  {'CI file':<42}{'parallel':>9}{'diff-cover80':>14}")
        for d, par, dc, present in rows:
            if not present:
                failures.append(f"{label}: CI template {d} missing")
            if REQUIRE_PARALLEL and not par:
                failures.append(f"{label}: CI file {d} has no sharding/parallel setting")
            if REQUIRE_DIFF_COVER and not dc:
                failures.append(f"{label}: CI file {d} lacks diff-cover --fail-under=80")
            print(f"  {d:<42}{'yes' if par else 'no':>9}{'yes' if dc else 'no':>14}")


def main():
    failures = []
    print("measure-outcomes: comments, suppressions, test size/band, exclusions, CI gates (static scan).")
    print("Not measured here: cognitive complexity, duplication, coverage — enforced by lint configs and CI.")
    if mode == "templates":
        for stack, kind in TEMPLATE_STACKS.items():
            base = os.path.join(root, "skills", "scaffold", stack, "template")
            if not os.path.isdir(base):
                failures.append(f"{stack}: template directory missing")
                continue
            report(stack, base, kind, root, failures)
    else:
        cands = [root] + [os.path.join(root, d) for d in sorted(os.listdir(root))
                          if os.path.isdir(os.path.join(root, d)) and d not in SKIP_DIRS and not d.startswith(".")]
        found = [(c, detect_stack(c)) for c in cands]
        found = [(c, s) for c, s in found if s]
        if not found:
            print("no known stack detected; measuring the directory as a whole")
            found = [(root, ("unknown", "py" if any(p.endswith(".py") for p in list_files(root)) else "ts"))]
        for c, (stack, kind) in found:
            report(f"{stack} ({os.path.relpath(c, root)})", c, kind, None, failures)
    print()
    if failures:
        print("FAIL: " + "\n      ".join(failures))
        return 1
    print("OK: all outcome metrics within thresholds")
    return 0


try:
    code = main()
except Exception as exc:
    print(f"measure-outcomes: internal error: {type(exc).__name__}: {exc}", file=sys.stderr)
    code = 2
sys.exit(code)
PY

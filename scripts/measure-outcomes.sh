#!/usr/bin/env bash
# scripts/measure-outcomes.sh — measures what generated code looks like. Static only: no installs,
# no network.
#
# Usage:
#   bash scripts/measure-outcomes.sh                  template mode: the four stack templates under skills/scaffold
#   bash scripts/measure-outcomes.sh PROJECT_DIR      project mode: a generated or migrated project
#   bash scripts/measure-outcomes.sh --baseline FILE PROJECT_DIR   project mode, then record the ratchet numbers in FILE
#   bash scripts/measure-outcomes.sh --compare FILE PROJECT_DIR    project mode, fail when a ratchet number got worse
# Environment: MO_REPO_ROOT points template mode at another checkout (used by the tests);
# every MO_* threshold below can be overridden, e.g. MO_MAX_COMMENT_PCT=8.
#
# TWO MODES, TWO EXIT CODE RULES
#   Template mode is a gate: exit 0 within every threshold, 1 when a number crosses one.
#   Project mode is a report: each metric prints beside its template reference value and is marked
#   WARN outside it; WARN never changes the exit code. Exit 1 only on a hard failure: an app with
#   zero test cases, no CI file enforcing the coverage gate (`diff-cover ... --fail-under=80` in at
#   least one CI file), or, with --compare, a ratchet number above its baseline. Exit 2: the tool
#   itself failed (unusable path or file, crash).
#   --baseline writes plain key=value lines (one per app and metric: suppressions, multiline, paren,
#   trailing; plus project.sonar_entries and project.coverage_gate). --compare reads that file and
#   fails when suppressions, Sonar exclusion entries (properties file plus CI pipeline), trailing
#   comments, multi-line comment blocks or parenthetical comments rise above it, or when the
#   coverage gate disappears. A migrated project records once, then never gets worse.
#
# WHAT THIS MEASURES (and what it does not)
#   Comments, in the detected stack's own files (.py for Python; .ts/.tsx/.js/.jsx/.mjs/.cjs for
#   TypeScript), source, tests and config alike: whole-line comments, runs of 2+ consecutive comment
#   lines (a blank line ends a run), comment lines holding a (parenthetical), and trailing inline
#   comments (code followed by // or # on the same line, found by a line-based scan that skips quoted
#   text). Suppressions in those files. Source and test LOC, test cases (it/test/def test_; an
#   it.each or test.each counts as one case; commented-out lines are skipped), test:source LOC ratio.
#   Lint/test-runner/coverage/Sonar exclusions (sonar-project.properties and -Dsonar.* or
#   extraProperties entries in CI files, with file:line). CI sharding and the diff-cover 80% gate.
#   A repo with several apps (a Python backend and a TS frontend) is reported per app, each counted
#   in its own language only. Paths under .git, node_modules, .venv, build, dist, .next, coverage,
#   .turbo, .claude/.harness-base and .claude/hooks are never scanned.
#   It does NOT measure cognitive complexity, duplication or coverage: the lint configs and CI
#   (SonarQube default gate: complexity 15, duplication 3%, coverage 80% on new code) enforce those.
#
# THRESHOLDS ARE A RATCHET: set just above today's templates so a regression fails. Tighten them as
# the numbers drop; never raise one to make a run pass. Known gap: the FastAPI template carries far
# more comments (about 24%) than the TypeScript stacks (3-8%); the limit is not tuned to it.
# In project mode the same values are only the reference column.
#   MO_MAX_COMMENT_PCT, MO_MAX_MULTILINE, MO_MAX_PAREN, MO_MAX_TRAILING: comment noise; tighten once
#     the comment policy lands.
#   MO_MAX_SUPPRESSIONS: eslint-disable, noqa, type: ignore, ts-expect-error, NOSONAR, coverage pragmas.
#   MO_MAX_EXCLUSIONS: lint + test-runner/coverage + Sonar exclusion entries; tighten once config is trimmed.
#   MO_MIN_TEST_RATIO / MO_MAX_TEST_RATIO: test LOC per 100 source LOC, a band, not a cap.
#     Floor: a project with no tests must fail, and 80% coverage on new code needs a real suite.
#     Ceiling: oversized, duplicated suites cost CI time and maintenance; the owner wants fewer,
#     consolidated tests. A high ratio is a prompt to consolidate duplicate tests, not to delete
#     coverage. Tighten the ceiling as suites are consolidated; a project is never failed on it.
#   MO_MIN_TESTS: minimum test cases (template mode; project mode hard-fails on 0).
#   MO_REQUIRE_PARALLEL=1: a template CI file without sharding/parallel settings fails (off until templates shard).
#   MO_REQUIRE_DIFF_COVER=1: a template CI file without `diff-cover ... --fail-under=80` fails.
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
USAGE="usage: $0 [--baseline FILE | --compare FILE] [PROJECT_DIR]"
BASELINE="" COMPARE="" PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) [[ $# -ge 2 && -z "$BASELINE" ]] || { echo "$USAGE" >&2; exit 2; }; BASELINE=$2; shift 2 ;;
    --compare) [[ $# -ge 2 && -z "$COMPARE" ]] || { echo "$USAGE" >&2; exit 2; }; COMPARE=$2; shift 2 ;;
    -*) echo "$USAGE" >&2; exit 2 ;;
    *) [[ -z "$PROJECT" ]] || { echo "$USAGE" >&2; exit 2; }; PROJECT=$1; shift ;;
  esac
done
if [[ -n "$BASELINE" && -n "$COMPARE" ]] || { [[ -n "$BASELINE$COMPARE" ]] && [[ -z "$PROJECT" ]]; }; then
  echo "$USAGE" >&2; exit 2
fi
MODE=templates
TARGET=${MO_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
if [[ -n "$PROJECT" ]]; then
  MODE=project
  [[ -d "$PROJECT" ]] || { echo "measure-outcomes: not a directory: $PROJECT" >&2; exit 2; }
  TARGET=$(cd "$PROJECT" && pwd)
elif [[ ! -d "$TARGET/skills/scaffold" ]]; then
  echo "measure-outcomes: no skills/scaffold under $TARGET" >&2
  exit 2
fi

export MO_MAX_COMMENT_PCT MO_MAX_MULTILINE MO_MAX_PAREN MO_MAX_TRAILING MO_MAX_SUPPRESSIONS \
  MO_MAX_EXCLUSIONS MO_MIN_TEST_RATIO MO_MAX_TEST_RATIO MO_MIN_TESTS MO_REQUIRE_PARALLEL MO_REQUIRE_DIFF_COVER
exec python3 -I - "$MODE" "$TARGET" "$BASELINE" "$COMPARE" <<'PY'
import os, re, subprocess, sys

mode, root, baseline_out, compare_in = sys.argv[1:5]
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
CODE_EXT = {"py": {".py"}, "ts": {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"}}
SKIP_DIRS = {"node_modules", ".next", "dist", "build", "__pycache__", "coverage", ".venv", "venv", ".git", ".turbo"}
SKIP_PREFIXES = ((".claude", ".harness-base"), (".claude", "hooks"))
SUPPRESS = re.compile(
    r"eslint-disable|noqa|type:\s*ignore|pyright:\s*ignore|@ts-expect-error|@ts-ignore|@ts-nocheck"
    r"|NOSONAR|pragma:\s*no cover|istanbul ignore|v8 ignore|c8 ignore")
TEST_CASE_TS = re.compile(r"(?<![.\w])(?:it|test)(?:\.(?:each|only|skip|concurrent))*\s*(?:\(|`)")
TEST_CASE_PY = re.compile(r"^\s*(?:async\s+)?def test_", re.M)
SHARD = re.compile(r"--shard|shard:|matrix:|-n\s+auto|-n\s+\d|xdist|maxWorkers|--parallel|strategy:\s*parallel|pytest-split|--splits", re.I)
DIFF_COVER = re.compile(r"diff-cover[^\n]*--fail-under[= ]80\b")
CI_FILE = re.compile(r"(^|/)(\.github/workflows/[^/]+\.ya?ml|azure-pipelines[^/]*\.ya?ml|azure-pipelines/.+\.ya?ml)$")
SONAR_KEYS = ("sonar.exclusions", "sonar.coverage.exclusions", "sonar.cpd.exclusions", "sonar.test.exclusions")
SONAR_CI = re.compile(r"(sonar\.(?:exclusions|coverage\.exclusions|cpd\.exclusions|test\.exclusions))\s*[=:]\s*((?:(?!\s-D)[^\n])*)")


def skipped(rel_parts):
    if SKIP_DIRS.intersection(rel_parts[:-1]):
        return True
    return any(tuple(rel_parts[:len(pre)]) == pre for pre in SKIP_PREFIXES)


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
    return sorted(p for p in out if not skipped(os.path.relpath(p, base).split(os.sep)))


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


def count_tests(text, py):
    if py:
        return len(TEST_CASE_PY.findall(text))
    n = 0
    for ln in text.splitlines():
        s = ln.lstrip()
        if s.startswith(("//", "/*", "*")):
            continue
        n += len(TEST_CASE_TS.findall(s))
    return n


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


def measure(base, kind, exclude=()):
    files = [p for p in list_files(base) if not any(p.startswith(x + os.sep) for x in exclude)]
    m = dict(src_files=0, src_loc=0, test_files=0, test_loc=0, tests=0, cl=0, runs=0, paren=0, trail=0, supp=0)
    code_files = [p for p in files if os.path.splitext(p)[1] in CODE_EXT[kind]]
    has_src = any("src" in comps(p, base)[:-1] for p in code_files)
    src_stems, test_stems = set(), []
    py = kind == "py"
    for p in code_files:
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
            m["tests"] += count_tests(text, py)
            test_stems.append(stem)
        elif "src" in comps(p, base)[:-1] or not has_src:
            m["src_files"] += 1
            m["src_loc"] += code
            src_stems.add(stem)
    m["orphan_tests"] = sum(1 for s in test_stems if s not in src_stems)
    lint, cov, sonar, sonar_file = config_entries(base, files)
    return m, files, lint, cov, sonar, sonar_file


def template_ci_rows(tmpl_root, kind):
    rows = []
    for d in CI_DIRS[kind]:
        tdir = os.path.join(tmpl_root, "skills", "scaffold", "shared", "template-ci", d)
        text = "".join(read(p) for p in list_files(tdir)) if os.path.isdir(tdir) else ""
        rows.append((d, bool(SHARD.search(text)), bool(DIFF_COVER.search(text)), bool(text)))
    return rows


def project_ci(base):
    """CI files of the whole project: (rows, sonar entries as (file, line, key, entries))."""
    rows, sonar = [], []
    for p in list_files(base):
        rel = os.path.relpath(p, base)
        if not CI_FILE.search(rel):
            continue
        text = read(p)
        rows.append((rel, bool(SHARD.search(text)), bool(DIFF_COVER.search(text))))
        for i, ln in enumerate(text.splitlines(), 1):
            for m in SONAR_CI.finditer(ln):
                val = m.group(2).strip().strip("'\"|")
                entries = [x.strip().strip("'\"") for x in val.split(",") if x.strip().strip("'\"")]
                if entries:
                    sonar.append((rel, i, m.group(1), entries))
    return rows, sonar


def app_values(m, lint, cov, sonar):
    total = m["cl"] + m["src_loc"] + m["test_loc"]
    return {
        "comment %": 100.0 * m["cl"] / total if total else 0.0,
        "multi-line comments": m["runs"], "parenthetical comments": m["paren"],
        "trailing inline comments": m["trail"], "suppressions": m["supp"],
        "exclusions (all kinds)": len(lint) + len(cov) + sum(len(v) for v in sonar.values()),
        "test cases": m["tests"],
        "test LOC per 100 src LOC": 100.0 * m["test_loc"] / m["src_loc"] if m["src_loc"] else 0.0,
    }


def print_app(label, m, values, lint, cov, sonar, sonar_file, gate, warns, failures):
    print(f"\n== {label} ==")
    print(f"  source files {m['src_files']}, source LOC {m['src_loc']}, test files {m['test_files']}, "
          f"test LOC {m['test_loc']}, test cases {m['tests']}, comment lines {m['cl']}")
    print(f"  test files with no same-named source file (info only): {m['orphan_tests']}")
    print(f"  {'metric':<27}{'value':>9}{'ref' if not gate else 'limit':>10}  status")
    for k, lim, kindl in LIMITS:
        v = values[k]
        bad = v > lim if kindl == "max" else v < lim
        if bad and gate:
            failures.append(f"{label}: {k} {v:.2f} {'>' if kindl == 'max' else '<'} {lim} ({kindl})")
        elif bad:
            warns.append(f"{label}: {k} {v:.2f}")
        status = ("FAIL" if gate else "WARN") if bad else "ok"
        print(f"  {k:<27}{v:>9.2f}{('<=' if kindl == 'max' else '>=') + str(lim):>10}  {status}")
    if not gate:
        print("  A high test:source ratio is a prompt to consolidate duplicate tests, not to delete coverage.")
    print(f"  lint ignores {len(lint)}: {', '.join(lint) or '-'}")
    print(f"  vitest/pytest/coverage excludes {len(cov)}: {', '.join(cov) or '-'}")
    if sonar_file:
        print(f"  Sonar ({sonar_file}):")
        for k in SONAR_KEYS:
            print(f"    {k} {len(sonar.get(k, []))}: {', '.join(sonar.get(k, [])) or '-'}")
    else:
        print("  Sonar: no sonar-project.properties found")


def run_templates(failures):
    for stack, kind in TEMPLATE_STACKS.items():
        base = os.path.join(root, "skills", "scaffold", stack, "template")
        if not os.path.isdir(base):
            failures.append(f"{stack}: template directory missing")
            continue
        m, files, lint, cov, sonar, sonar_file = measure(base, kind)
        print_app(stack, m, app_values(m, lint, cov, sonar), lint, cov, sonar, sonar_file, True, [], failures)
        rows = template_ci_rows(root, kind)
        print(f"  {'CI file':<42}{'parallel':>9}{'diff-cover80':>14}")
        for d, par, dc, present in rows:
            if not present:
                failures.append(f"{stack}: CI template {d} missing")
            if REQUIRE_PARALLEL and not par:
                failures.append(f"{stack}: CI file {d} has no sharding/parallel setting")
            if REQUIRE_DIFF_COVER and not dc:
                failures.append(f"{stack}: CI file {d} lacks diff-cover --fail-under=80")
            print(f"  {d:<42}{'yes' if par else 'no':>9}{'yes' if dc else 'no':>14}")


def parse_kv(path):
    out = {}
    with open(path, encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.strip()
            if ln and not ln.startswith("#") and "=" in ln:
                k, v = ln.split("=", 1)
                out[k.strip()] = int(v.strip())
    return out


def run_project(failures):
    cands = [root] + [os.path.join(root, d) for d in sorted(os.listdir(root))
                      if os.path.isdir(os.path.join(root, d)) and d not in SKIP_DIRS and not d.startswith(".")]
    found = [(c, detect_stack(c)) for c in cands]
    found = [(c, s) for c, s in found if s]
    if not found:
        print("no known stack detected; measuring the directory as a whole")
        has_py = any(p.endswith(".py") for p in list_files(root))
        found = [(root, ("unknown", "py" if has_py else "ts"))]
    warns, current = [], {}
    sonar_props = 0
    for c, (stack, kind) in found:
        children = [x for x, _ in found if x != c and x.startswith(c + os.sep)]
        m, files, lint, cov, sonar, sonar_file = measure(c, kind, children)
        rel = os.path.relpath(c, root)
        label = f"{stack} ({rel})"
        print_app(label, m, app_values(m, lint, cov, sonar), lint, cov, sonar, sonar_file, False, warns, failures)
        if m["tests"] == 0:
            failures.append(f"{label}: zero test cases")
        key = f"{stack}@{rel}"
        current.update({f"{key}.suppressions": m["supp"], f"{key}.multiline": m["runs"],
                        f"{key}.paren": m["paren"], f"{key}.trailing": m["trail"]})
        sonar_props += sum(len(v) for v in sonar.values())
    rows, sonar_ci = project_ci(root)
    print("\n== project CI ==")
    if rows:
        print(f"  {'CI file':<42}{'parallel':>9}{'diff-cover80':>14}")
        for d, par, dc in rows:
            print(f"  {d:<42}{'yes' if par else 'no':>9}{'yes' if dc else 'no':>14}")
    gate_files = [d for d, _, dc in rows if dc]
    if gate_files:
        print(f"  coverage gate (diff-cover --fail-under=80): found in {', '.join(gate_files)}")
    else:
        failures.append("project: no CI file enforces the coverage gate (diff-cover --fail-under=80)")
    ci_entries = sum(len(e) for _, _, _, e in sonar_ci)
    print(f"  Sonar exclusion entries passed in CI: {ci_entries}")
    for rel, i, key, entries in sonar_ci:
        print(f"    {rel}:{i} {key}: {', '.join(entries)}")
    current["project.sonar_entries"] = sonar_props + ci_entries
    current["project.coverage_gate"] = 1 if gate_files else 0
    if baseline_out:
        with open(baseline_out, "w", encoding="utf-8") as fh:
            fh.write("# measure-outcomes baseline: a project may not get worse than these numbers\n")
            fh.writelines(f"{k}={v}\n" for k, v in sorted(current.items()))
        print(f"\nbaseline written to {baseline_out} ({len(current)} values)")
    if compare_in:
        base = parse_kv(compare_in)
        print(f"\n== ratchet vs {compare_in} ==")
        for k, v in sorted(base.items()):
            cur = current.get(k)
            if cur is None:
                print(f"  {k}: not measured now (baseline {v})")
                continue
            worse = cur < v if k.endswith("coverage_gate") else cur > v
            print(f"  {k}: {cur} (baseline {v}) {'WORSE' if worse else 'ok'}")
            if worse:
                failures.append(f"ratchet: {k} {cur} is worse than baseline {v}")
    if warns:
        print(f"\n{len(warns)} WARN (report only, exit code unaffected): " + "; ".join(warns))


def main():
    failures = []
    print("measure-outcomes: comments, suppressions, test size/band, exclusions, CI gates (static scan).")
    print("Not measured here: cognitive complexity, duplication, coverage — enforced by lint configs and CI.")
    if mode == "templates":
        run_templates(failures)
    else:
        print("Project mode is a report: WARN marks a value outside the template reference; only hard failures set the exit code.")
        run_project(failures)
    print()
    if failures:
        print("FAIL: " + "\n      ".join(failures))
        return 1
    print("OK: all outcome metrics within thresholds" if mode == "templates" else "OK: no hard failure")
    return 0


try:
    code = main()
except Exception as exc:
    print(f"measure-outcomes: internal error: {type(exc).__name__}: {exc}", file=sys.stderr)
    code = 2
sys.exit(code)
PY

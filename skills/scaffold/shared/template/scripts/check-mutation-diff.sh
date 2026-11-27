#!/usr/bin/env bash
# Diff-scoped mutation gate: runs the seeded mutation tool only on the source files this change touches, and fails on any mutant a test does not kill.
# Tools: StrykerJS (stryker.config.mjs, nextjs, nestjs, vite-react) and mutmut ([tool.mutmut] in pyproject.toml, fastapi), the two that templatecentral:add mutation-testing seeds. No other tool is run. Offline: nothing here calls a network.
# Base: argument, else GATE_BASE, else origin/main, then the merge base with HEAD. Committed, staged, unstaged and untracked-but-not-ignored source files all count. Run from any folder of the repository: the gate works from the repository root and finds each app (backend/, frontend/, any folder) by its tool config.
# Files judged: a changed file the base version of the tool config selects (Stryker mutate globs, mutmut source_paths), found by name in the diff with every attribute, textconv and rename option off, so .gitattributes lines and pathspec-like file names cannot hide it. A changed file whose name holds a character outside letters, digits and . _ / @ + = - fails, because the tool's file selection would read it as a glob.
# The tool config is compared with the merge base: a new Stryker ! exclude, a removed mutate entry, a lower or removed thresholds.break, a new mutmut do_not_mutate entry, a removed source_paths entry, a deleted config, and a new "Stryker disable" or "pragma: no mutate" comment in a judged file each fail and name the change. The gate never passes a threshold or an exclude to the tool.
# A survivor (Stryker Survived or NoCoverage, mutmut survived or no tests) fails and names file, line and mutator (mutmut names no mutator, so the changed source line is shown). A report that is empty, malformed, missing a judged file, or lists no judged mutant for a file that has code fails.
# CPU cap: MUTATION_DIFF_CPU_SECONDS (default 900), applied with ulimit -t to the tool and each process it starts. A run the cap ends fails with its own message. In CI a value above the default is refused.
# Not set up: no tool config anywhere, or the tool missing locally: one "not set up" line naming templatecentral:add mutation-testing, exit 0. In CI (CI, GITHUB_ACTIONS or TF_BUILD set) a config with the tool missing fails. Unresolved base: nothing checked locally, a failure in CI.
# Exit: 0 clean, set up with nothing to judge, or not set up; 1 a survivor or a rule broken; 2 it could not run (no git, no interpreter, bad cap, unreadable input, unresolved base in CI).
# Not caught: a developer who edits files outside git and the hooks on their own machine and never opens a PR; git commit --no-verify locally (CI still runs the gate); equivalent mutants; code the mutation tool cannot mutate; a contract-free file the tool reports no mutant for because it has none; stacks or tools the plugin does not seed; a cap that a tool dodges by running as many short processes.
# Usage: bash scripts/check-mutation-diff.sh [base-ref]        Env: GATE_BASE, MUTATION_DIFF_CPU_SECONDS.
set -uo pipefail
export LC_ALL=C
# Every git call reads a path literally, so a file name that looks like pathspec magic is a plain name.
export GIT_LITERAL_PATHSPECS=1

CAP_DEFAULT=900
ADD_HINT='run templatecentral:add mutation-testing to set it up'

die() {
  printf 'check-mutation-diff: %s\n' "$1" >&2
  exit 2
}

# True in GitHub Actions, Azure Pipelines or any run that sets CI.
is_ci() {
  case "${CI:-}${GITHUB_ACTIONS:-}${TF_BUILD:-}" in
    '') return 1 ;;
  esac
  case "${CI:-}" in [Ff][Aa][Ll][Ss][Ee] | 0) ;; *[!\ ]*) return 0 ;; esac
  case "${GITHUB_ACTIONS:-}${TF_BUILD:-}" in *[Tt][Rr][Uu][Ee]*) return 0 ;; esac
  return 1
}

failed=0
# Prints a failure line and marks the run failed, so every broken rule shows in one run.
fail() {
  printf 'check-mutation-diff: FAIL: %s\n' "$1" >&2
  failed=1
}

cap=${MUTATION_DIFF_CPU_SECONDS:-$CAP_DEFAULT}
case "$cap" in
  '' | *[!0-9]* | 0) die "MUTATION_DIFF_CPU_SECONDS must be a whole number above 0 (got '$cap')" ;;
esac
if is_ci && [ "$cap" -gt "$CAP_DEFAULT" ]; then
  die "MUTATION_DIFF_CPU_SECONDS=$cap is above the default $CAP_DEFAULT, which can widen the gate. It is not allowed in CI."
fi

command -v git > /dev/null 2>&1 || die "git is not installed"
top=$(git rev-parse --show-toplevel 2> /dev/null) || die "not a git repository"
cd "$top" || die "cannot enter $top"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-mutation-diff.XXXXXX") || die "cannot create a temporary folder in ${TMPDIR:-/tmp}"
trap 'rm -rf "$tmp"' EXIT

base=${1:-${GATE_BASE:-origin/main}}
mb=
if git rev-parse --verify --quiet "${base}^{commit}" > /dev/null 2>&1; then
  mb=$(git merge-base "$base" HEAD 2> /dev/null) || mb=
fi
if [ -z "$mb" ]; then
  if is_ci; then
    die "base ref '$base' not found or has no merge base with HEAD, so the changed files are unknown. Fetch it (git fetch origin main with full history) or pass another base ref."
  fi
  echo "check-mutation-diff: nothing checked: base ref '$base' not found. Fetch it or pass a base ref."
  exit 0
fi

# Writes the changed and untracked file names, NUL separated, to $1. Added, copied, modified and renamed files only.
list_changed() {
  git -c core.quotepath=false diff --name-only -z --no-renames --no-textconv --no-ext-diff --no-color --diff-filter=ACMRT "$mb" > "$1" 2> "$tmp/err.txt" || die "git diff failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
  git -c core.quotepath=false ls-files -z --others --exclude-standard >> "$1" 2> "$tmp/err.txt" || die "git ls-files failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
}

# Counts lines of file $1 that start with the mutmut section header, into stdout.
mutmut_section() {
  local n
  n=$(grep -c -e '^\[tool\.mutmut\][[:space:]]*$' -- "$1" 2> "$tmp/err.txt")
  if [ $? -gt 1 ]; then die "cannot read $1: $(head -n 1 "$tmp/err.txt")"; fi
  echo "$n"
}

# Finds every tool config at HEAD (working tree) into roots.txt as "tool<TAB>dir", and fails when one at the merge base is gone.
: > "$tmp/roots.txt"
: > "$tmp/all.z"
list_changed "$tmp/changed.z"
git -c core.quotepath=false ls-files -z --cached --others --exclude-standard > "$tmp/all.z" 2> "$tmp/err.txt" || die "git ls-files failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
while IFS= read -r -d '' p; do
  case "$p" in *$'\n'*) die "a file name holds a line break: refusing to read it" ;; esac
  d=$(dirname "$p")
  case "${p##*/}" in
    stryker.config.mjs)
      [ -f "$p" ] && printf 'stryker\t%s\n' "$d" >> "$tmp/roots.txt"
      ;;
    pyproject.toml)
      if [ -f "$p" ] && [ "$(mutmut_section "$p")" -gt 0 ]; then printf 'mutmut\t%s\n' "$d" >> "$tmp/roots.txt"; fi
      ;;
  esac
done < "$tmp/all.z"
sort -u "$tmp/roots.txt" > "$tmp/roots.sorted" || die "cannot sort the config list"
mv "$tmp/roots.sorted" "$tmp/roots.txt" || die "cannot update the config list"

git ls-tree -r -z --name-only "$mb" > "$tmp/mbtree.z" 2> "$tmp/err.txt" || die "git ls-tree failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
while IFS= read -r -d '' p; do
  case "${p##*/}" in
    stryker.config.mjs)
      if [ ! -f "$p" ]; then fail "$p exists at the merge base and is gone: a change cannot delete the mutation config to skip the gate."; fi
      ;;
    pyproject.toml)
      git show "$mb:$p" > "$tmp/base.toml" 2> "$tmp/err.txt" || die "cannot read $p at the merge base: $(head -n 1 "$tmp/err.txt")"
      if [ "$(mutmut_section "$tmp/base.toml")" -gt 0 ]; then
        if [ ! -f "$p" ] || [ "$(mutmut_section "$p")" -eq 0 ]; then fail "$p has [tool.mutmut] at the merge base and no longer does: a change cannot remove the mutation config to skip the gate."; fi
      fi
      ;;
  esac
done < "$tmp/mbtree.z"

if [ ! -s "$tmp/roots.txt" ]; then
  if [ "$failed" -eq 1 ]; then exit 1; fi
  echo "check-mutation-diff: not set up: no stryker.config.mjs and no [tool.mutmut] in pyproject.toml, so no mutation testing runs. To add it, $ADD_HINT."
  exit 0
fi

# Writes the helper scripts. The node helper reads a Stryker config and report; the python helper reads a mutmut config and report.
cat > "$tmp/helper.mjs" << 'NODE_HELPER' || die "cannot write the node helper"
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const out = (...f) => process.stdout.write(f.join("\t") + "\n");
const esc = (c) => c.replace(/[\\^$.*+?()[\]{}|/-]/g, "\\$&");

function globToRe(g) {
  let r = "^";
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === "*") {
      if (g[i + 1] === "*") {
        if (g[i + 2] === "/") { r += "(?:.*/)?"; i += 2; } else { r += ".*"; i += 1; }
      } else r += "[^/]*";
    } else if (c === "?") r += "[^/]";
    else if (c === "{") {
      const j = g.indexOf("}", i);
      if (j < 0) throw new Error("unclosed { in glob " + g);
      r += "(?:" + g.slice(i + 1, j).split(",").map(esc).join("|") + ")";
      i = j;
    } else r += esc(c);
  }
  return new RegExp(r + "$");
}

async function load(file) {
  const mod = await import(pathToFileURL(file).href);
  const cfg = mod.default;
  if (!cfg || typeof cfg !== "object") throw new Error("no default export object in " + file);
  if (!Array.isArray(cfg.mutate) || cfg.mutate.length === 0 || cfg.mutate.some((m) => typeof m !== "string")) {
    throw new Error("mutate must be a non-empty array of strings in " + file);
  }
  const b = cfg.thresholds && "break" in cfg.thresholds ? cfg.thresholds.break : null;
  if (b !== null && typeof b !== "number") throw new Error("thresholds.break must be a number or null in " + file);
  return { mutate: cfg.mutate, brk: b };
}

// Removes comments, then import lines and type or interface declarations, so a type-only file counts as no code.
function hasCode(src) {
  let t = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  const re = /^[ \t]*(?:export\s+)?(?:declare\s+)?(?:import\b|type\s+\w|interface\s+\w|export\s*\*|export\s*\{)/m;
  for (;;) {
    const m = re.exec(t);
    if (!m) break;
    let i = m.index, depth = 0;
    for (; i < t.length; i++) {
      const c = t[i];
      if ("{([".includes(c)) depth++;
      else if ("})]".includes(c)) depth--;
      else if (depth <= 0 && c === ";") { i++; break; }
      else if (depth <= 0 && c === "\n") {
        const before = t.slice(m.index, i).trimEnd();
        const after = t.slice(i).trimStart()[0] || "";
        if (!"=|&,<:".includes(before.slice(-1)) && !"|&=?:.,<>".includes(after)) { i++; break; }
      }
    }
    t = t.slice(0, m.index) + "\n" + t.slice(i);
  }
  return /[()!?&|+\-*/%<>"'`]/.test(t);
}

function gitShow(mb, p) {
  try {
    return execFileSync("git", ["show", mb + ":" + p], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 1 << 28 });
  } catch { return ""; }
}
const disables = (s) => (s.match(/Stryker\s+disable/g) || []).length;

const [, , cmd, ...a] = process.argv;
try {
  if (cmd === "plan") {
    // plan <head config> <base config or -> <changed list> <mb> <prefix>
    const [headF, baseF, listF, mb, prefix] = a;
    const head = await load(headF);
    const base = baseF === "-" ? null : await load(baseF);
    if (base) {
      for (const m of head.mutate) if (m.startsWith("!") && !base.mutate.includes(m)) out("FAIL", "mutate gained an exclude not on the base branch: " + m + ". A change cannot exclude its own files from mutation testing.");
      for (const m of base.mutate) if (!head.mutate.includes(m)) out("FAIL", "mutate entry removed from the config: " + m + ". A change cannot narrow what is mutated.");
      if (base.brk !== null && (head.brk === null || head.brk < base.brk)) out("FAIL", "thresholds.break went from " + base.brk + " to " + head.brk + ". A change cannot lower the score threshold.");
    }
    const use = base || head;
    const pos = use.mutate.filter((m) => !m.startsWith("!")).map(globToRe);
    const neg = use.mutate.filter((m) => m.startsWith("!")).map((m) => globToRe(m.slice(1)));
    const files = readFileSync(listF, "utf8").split("\0").filter(Boolean);
    for (const f of files) {
      if (!pos.some((r) => r.test(f)) || neg.some((r) => r.test(f))) continue;
      if (!/^[A-Za-z0-9._/@+=-]+$/.test(f)) { out("FAIL", "changed source file '" + f + "' has a character the mutation tool would read as a glob. Rename it, or add it to the base config's exclusions on the base branch."); continue; }
      const now = readFileSync(f, "utf8");
      if (disables(now) > disables(gitShow(mb, prefix + f))) { out("FAIL", f + " gains a 'Stryker disable' comment, which hides mutants from the gate."); continue; }
      out("RUN", f, hasCode(now) ? "code" : "nocode");
    }
  } else if (cmd === "reportpath") {
    // reportpath <config>: where the json reporter writes, relative to the project root
    const mod = await import(pathToFileURL(a[0]).href);
    const jr = mod.default && mod.default.jsonReporter;
    const fn = jr && "fileName" in jr ? jr.fileName : "reports/mutation/mutation.json";
    if (typeof fn !== "string" || fn === "" || fn.startsWith("/") || fn.split("/").includes("..")) out("FAIL", "jsonReporter.fileName must be a relative path inside the project, got " + JSON.stringify(fn));
    else out("PATH", fn);
  } else if (cmd === "report") {
    // report <report.json> <run list: file<TAB>code|nocode per line>
    const [repF, runF] = a;
    const text = readFileSync(repF, "utf8");
    if (text.trim() === "") { out("FAIL", "the mutation report is empty"); process.exit(0); }
    let rep;
    try { rep = JSON.parse(text); } catch (e) { out("FAIL", "the mutation report is not valid JSON (" + e.message + "): truncated or malformed"); process.exit(0); }
    if (!rep || typeof rep !== "object" || rep.schemaVersion === undefined || !rep.files || typeof rep.files !== "object") { out("FAIL", "the mutation report has no schemaVersion or files object"); process.exit(0); }
    const run = readFileSync(runF, "utf8").split("\n").filter(Boolean).map((l) => l.split("\t"));
    const killedOk = new Set(["Killed", "Timeout", "CompileError", "Ignored"]);
    for (const [f, code] of run) {
      const key = Object.keys(rep.files).find((k) => k.replace(/\\/g, "/").replace(/^\.\//, "") === f);
      if (key === undefined) { out("FAIL", f + " is not in the mutation report, so it was not judged"); continue; }
      const ms = rep.files[key].mutants;
      if (!Array.isArray(ms)) { out("FAIL", f + " has no mutants array in the report"); continue; }
      let judged = 0, killed = 0, bad = false;
      for (const m of ms) {
        const line = m && m.location && m.location.start && m.location.start.line;
        if (!m || typeof m.status !== "string" || typeof m.mutatorName !== "string" || !Number.isInteger(line)) { out("FAIL", f + " has a mutant with no status, mutatorName or start line in the report"); bad = true; break; }
        if (m.status !== "Ignored") judged++;
        if (m.status === "Killed" || m.status === "Timeout") killed++;
        if (!killedOk.has(m.status)) out("SURVIVOR", f, String(line), m.mutatorName, m.status);
      }
      if (bad) continue;
      if (judged === 0 && code === "code") out("FAIL", f + " has code and the report lists no judged mutant for it (" + ms.length + " ignored): it was not mutated");
      else out("OK", f, String(killed), String(judged));
    }
  } else throw new Error("unknown command " + cmd);
} catch (e) {
  out("FAIL", String(e && e.message ? e.message : e));
}
NODE_HELPER

cat > "$tmp/helper.py" << 'PY_HELPER' || die "cannot write the python helper"
import fnmatch
import io
import re
import subprocess
import sys
import tokenize


def out(*fields):
    sys.stdout.write("\t".join(fields) + "\n")


def load(path):
    try:
        import tomllib
    except ImportError:
        raise ValueError("this python3 is older than 3.11 and has no tomllib: use the project's .venv or python 3.11 or newer")
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    cfg = data.get("tool", {}).get("mutmut")
    if not isinstance(cfg, dict):
        raise ValueError("no [tool.mutmut] table in " + path)
    paths = cfg.get("source_paths", [])
    skip = cfg.get("do_not_mutate", [])
    for name, val in (("source_paths", paths), ("do_not_mutate", skip)):
        if not isinstance(val, list) or any(not isinstance(v, str) for v in val):
            raise ValueError(name + " must be a list of strings in " + path)
    if not paths:
        raise ValueError("source_paths must name at least one folder in " + path)
    return [p.rstrip("/") + "/" for p in paths], skip


def has_code(src):
    """True when the file has a logical line that is not an import, a docstring, pass or an ellipsis."""
    skip = {tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.ENDMARKER}
    line = []
    for tok in tokenize.generate_tokens(io.StringIO(src).readline):
        if tok.type == tokenize.NEWLINE or tok.type == tokenize.ENDMARKER:
            if line:
                first = line[0]
                only_string = all(t.type == tokenize.STRING for t in line)
                if first.string not in ("import", "from", "pass") and not only_string and [t.string for t in line] != ["..."]:
                    return True
            line = []
        elif tok.type not in skip:
            line.append(tok)
    return False


def git_show(mb, path):
    r = subprocess.run(["git", "show", mb + ":" + path], capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""


def pragmas(text):
    return len(re.findall(r"pragma:\s*no mutate", text))


cmd = sys.argv[1]
try:
    if cmd == "plan":
        head_f, base_f, list_f, mb, prefix = sys.argv[2:7]
        head_paths, head_skip = load(head_f)
        base = load(base_f) if base_f != "-" else None
        if base:
            for s in head_skip:
                if s not in base[1]:
                    out("FAIL", "do_not_mutate gained an entry not on the base branch: " + s + ". A change cannot exclude its own files from mutation testing.")
            for p in base[0]:
                if p not in head_paths:
                    out("FAIL", "source_paths entry removed from the config: " + p + ". A change cannot narrow what is mutated.")
        use_paths, use_skip = base if base else (head_paths, head_skip)
        with open(list_f, "rb") as fh:
            files = [x.decode("utf-8") for x in fh.read().split(b"\0") if x]
        for f in files:
            if not f.endswith(".py") or not any(f.startswith(p) for p in use_paths):
                continue
            if any(fnmatch.fnmatch(f, s) for s in use_skip):
                continue
            if not re.fullmatch(r"[A-Za-z0-9_/]+\.py", f):
                out("FAIL", "changed source file '" + f + "' has a name that cannot be a Python module path. Rename it.")
                continue
            with open(f, encoding="utf-8") as fh:
                now = fh.read()
            if pragmas(now) > pragmas(git_show(mb, prefix + f)):
                out("FAIL", f + " gains a 'pragma: no mutate' comment, which hides mutants from the gate.")
                continue
            root_p = max((p for p in use_paths if f.startswith(p)), key=len)
            module = f[len(root_p):-3].replace("/", ".")
            out("RUN", f, module, "code" if has_code(now) else "nocode")
    elif cmd == "results":
        res_f, run_f = sys.argv[2:4]
        ok = {"killed", "timeout", "skipped"}
        seen = {}
        files_of = {}
        for ln in open(run_f, encoding="utf-8").read().splitlines():
            f, module, code = ln.split("\t")
            files_of[module] = f
        for ln in open(res_f, encoding="utf-8").read().splitlines():
            m = re.fullmatch(r"\s+(\S+): (.+?)\s*", ln)
            if not m:
                continue
            name, status = m.groups()
            mod = name.rsplit(".", 1)[0] if "__mutmut_" in name else None
            if mod is None:
                out("FAIL", "unrecognised mutant name in the mutmut results: " + name)
                continue
            if mod not in files_of:
                continue
            seen.setdefault(mod, [0, 0])
            seen[mod][1] += 1
            if status in ("killed", "timeout"):
                seen[mod][0] += 1
            if status not in ok:
                out("SURVIVOR", files_of.get(mod, mod), name, status)
        for ln in open(run_f, encoding="utf-8").read().splitlines():
            f, module, code = ln.split("\t")
            k, n = seen.get(module, [0, 0])
            if n == 0 and code == "code":
                out("FAIL", f + " has code and mutmut lists no mutant for it: it was not mutated")
            else:
                out("OK", f, str(k), str(n))
    elif cmd == "diff":
        first = None
        old = new = ""
        cur = None
        for ln in open(sys.argv[2], encoding="utf-8").read().splitlines():
            h = re.match(r"@@ -(\d+)", ln)
            if h:
                cur = int(h.group(1))
                continue
            if cur is None or ln.startswith(("---", "+++")):
                continue
            if ln.startswith("-"):
                if first is None:
                    first, old = cur, ln[1:].strip()
                cur += 1
            elif ln.startswith("+"):
                if first is not None and not new:
                    new = ln[1:].strip()
            else:
                cur += 1
        if first is None:
            out("FAIL", "no changed line in the mutmut diff")
        else:
            out(str(first), old + " -> " + new)
    else:
        raise ValueError("unknown command " + cmd)
except Exception as e:
    out("FAIL", type(e).__name__ + ": " + str(e))
PY_HELPER

checked=0
survivors=0

# Prints the files of root $1 that no deeper root owns, relative to it, NUL separated, into $2.
files_of_root() {
  local root=$1 out=$2 p rest owner d
  : > "$out"
  while IFS= read -r -d '' p; do
    if [ "$root" = . ]; then
      rest=$p
    else
      case "$p" in "$root"/*) rest=${p#"$root"/} ;; *) continue ;; esac
    fi
    owner=0
    while IFS="$(printf '\t')" read -r _ d; do
      if [ "$d" = "$root" ]; then continue; fi
      if [ "$root" = . ]; then
        case "$p" in "$d"/*) owner=1 ;; esac
      else
        case "$d" in "$root"/*) case "$p" in "$d"/*) owner=1 ;; esac ;; esac
      fi
    done < "$tmp/roots.txt"
    if [ "$owner" -eq 1 ]; then continue; fi
    printf '%s\0' "$rest" >> "$out"
  done < "$tmp/changed.z"
}

# Handles a failure line list: prints each FAIL, marks the run failed.
report_fails() {
  local line
  while IFS= read -r line; do
    case "$line" in
      FAIL"$(printf '\t')"*) fail "$2: ${line#FAIL?}" ;;
    esac
  done < "$1"
}

# Sets CHILD_CPU to the whole CPU seconds, rounded up, that this shell's finished children have used. It runs in this shell: a pipe or command substitution forks and sees no children.
children_cpu() {
  times > "$tmp/times.txt"
  CHILD_CPU=$(awk 'NR == 2 { for (i = 1; i <= NF; i++) { split($i, p, /[ms]/); t += p[1] * 60 + p[2] } printf "%d", (t == int(t)) ? t : int(t) + 1 }' "$tmp/times.txt")
}

# Runs the tool command in $1 (a root) with the cpu cap; the rest are the command and its arguments. Sets TOOL_EC.
run_capped() {
  local root=$1 before
  shift
  children_cpu
  before=$CHILD_CPU
  (
    cd "$root" || exit 126
    ulimit -t "$cap" || exit 126
    PATH="$PWD/node_modules/.bin:$PWD/.venv/bin:$PATH" exec "$@"
  ) > "$tmp/tool.out" 2>&1
  TOOL_EC=$?
  children_cpu
  TOOL_CPU=$((CHILD_CPU - before))
}

# Prints the last lines of the tool output.
tool_tail() {
  tail -n 15 "$tmp/tool.out" | sed 's/^/check-mutation-diff:   | /' >&2
}

# True when the tool $2 is on the project's PATH (root $1).
tool_present() {
  (
    cd "$1" || exit 1
    PATH="$PWD/node_modules/.bin:$PWD/.venv/bin:$PATH" command -v "$2" > /dev/null 2>&1
  )
}

# Exit code of a process the cap ended: SIGXCPU is signal 24 (macOS), and Linux sends SIGKILL (137) when soft and hard limits are equal.
CAP_EC=152
KILL_EC=137

# Prints the reason and fails when the cap ended the run; returns 0 then.
cap_ended() {
  if [ "$TOOL_EC" -eq "$CAP_EC" ] || { [ "$TOOL_EC" -eq "$KILL_EC" ] && [ "$TOOL_CPU" -ge "$cap" ]; }; then
    fail "$1: the mutation run used more than $cap CPU seconds (MUTATION_DIFF_CPU_SECONDS) and was stopped. The result is unknown, so this is a failure, not a pass. Split the change into smaller pull requests."
    return 0
  fi
  return 1
}

# Judges one app root: $1 tool, $2 dir.
judge_root() {
  local tool=$1 root=$2 label n=0 py
  label=$root
  [ "$root" = . ] && label='the repository root'
  files_of_root "$root" "$tmp/rootfiles.z"
  local prefix=
  if [ "$root" != . ]; then prefix="$root/"; fi
  : > "$tmp/plan.txt"
  : > "$tmp/run.txt"
  if [ "$tool" = stryker ]; then
    command -v node > /dev/null 2>&1 || { fail "$label: node is not installed, so the Stryker config cannot be read. Install node."; return; }
    local basecfg=-
    if git cat-file -e "$mb:${prefix}stryker.config.mjs" 2> /dev/null; then
      git show "$mb:${prefix}stryker.config.mjs" > "$tmp/base-stryker.config.mjs" 2> "$tmp/err.txt" || die "cannot read the base config: $(head -n 1 "$tmp/err.txt")"
      basecfg=$tmp/base-stryker.config.mjs
    fi
    (cd "$root" && node "$tmp/helper.mjs" plan "$PWD/stryker.config.mjs" "$basecfg" "$tmp/rootfiles.z" "$mb" "$prefix") > "$tmp/plan.txt" 2> "$tmp/err.txt" || { fail "$label: the node helper stopped: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"; return; }
  else
    py=python3
    if [ -x "$top/${prefix}.venv/bin/python3" ]; then py="$top/${prefix}.venv/bin/python3"; fi
    command -v "$py" > /dev/null 2>&1 || { fail "$label: python3 is not installed, so pyproject.toml cannot be read. Install python3."; return; }
    local basecfg=-
    if git cat-file -e "$mb:${prefix}pyproject.toml" 2> /dev/null; then
      git show "$mb:${prefix}pyproject.toml" > "$tmp/base-pyproject.toml" 2> "$tmp/err.txt" || die "cannot read the base config: $(head -n 1 "$tmp/err.txt")"
      if [ "$(mutmut_section "$tmp/base-pyproject.toml")" -gt 0 ]; then basecfg=$tmp/base-pyproject.toml; fi
    fi
    (cd "$root" && "$py" -I "$tmp/helper.py" plan "$PWD/pyproject.toml" "$basecfg" "$tmp/rootfiles.z" "$mb" "$prefix") > "$tmp/plan.txt" 2> "$tmp/err.txt" || { fail "$label: the python helper stopped: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"; return; }
  fi
  report_fails "$tmp/plan.txt" "$label"
  grep -a '^RUN' "$tmp/plan.txt" > "$tmp/runs.txt"
  if [ $? -gt 1 ]; then die "cannot read the plan"; fi
  n=$(wc -l < "$tmp/runs.txt" | tr -d ' ')
  if [ "$n" -eq 0 ]; then return; fi
  if ! tool_present "$root" "$([ "$tool" = stryker ] && echo stryker || echo mutmut)"; then
    if is_ci; then
      fail "$label: the mutation config is present and the tool is not installed. Install it in the project ($ADD_HINT)."
    else
      echo "check-mutation-diff: not set up: $label has a mutation config and no $([ "$tool" = stryker ] && echo stryker || echo mutmut) tool installed. To add it, $ADD_HINT."
    fi
    return
  fi
  if [ "$tool" = stryker ]; then
    cut -f2- "$tmp/runs.txt" > "$tmp/run.txt"
    local list
    list=$(cut -f2 "$tmp/runs.txt" | tr '\n' ',' | sed 's/,$//')
    (cd "$root" && node "$tmp/helper.mjs" reportpath "$PWD/stryker.config.mjs") > "$tmp/rp.txt" 2> "$tmp/err.txt" || { fail "$label: the node helper stopped: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"; return; }
    report_fails "$tmp/rp.txt" "$label"
    local rpk rpath
    IFS="$(printf '\t')" read -r rpk rpath < "$tmp/rp.txt"
    if [ "$rpk" != PATH ]; then return; fi
    rm -f "$root/$rpath"
    run_capped "$root" stryker run --mutate "$list" --reporters json
    if cap_ended "$label"; then return; fi
    cp "$root/$rpath" "$tmp/report.json" 2> /dev/null
    if [ ! -s "$tmp/report.json" ]; then
      fail "$label: stryker exited $TOOL_EC and wrote no report, so nothing was judged."
      tool_tail
      return
    fi
    (cd "$root" && node "$tmp/helper.mjs" report "$tmp/report.json" "$tmp/run.txt") > "$tmp/res.txt" 2> "$tmp/err.txt" || { fail "$label: the node helper stopped: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"; return; }
    report_fails "$tmp/res.txt" "$label"
    local f l m s
    while IFS="$(printf '\t')" read -r kind f l m s; do
      if [ "$kind" = SURVIVOR ]; then
        fail "$label: surviving mutant in ${prefix}$f line $l, mutator $m ($s). Add or strengthen a test that fails when this change is made."
        survivors=$((survivors + 1))
      fi
    done < "$tmp/res.txt"
    if [ "$TOOL_EC" -ne 0 ] && [ "$survivors" -eq 0 ] && ! grep -a -q '^FAIL' "$tmp/res.txt"; then
      fail "$label: stryker exited $TOOL_EC with no survivor listed: it failed its own threshold or stopped on an error."
      tool_tail
    fi
  else
    cut -f2- "$tmp/runs.txt" > "$tmp/run.txt"
    set --
    while IFS= read -r mod; do set -- "$@" "$mod*"; done < <(cut -f3 "$tmp/runs.txt")
    run_capped "$root" mutmut run "$@"
    if cap_ended "$label"; then return; fi
    if [ "$TOOL_EC" -ne 0 ]; then
      fail "$label: mutmut run exited $TOOL_EC."
      tool_tail
      return
    fi
    run_capped "$root" mutmut results --all true
    if [ "$TOOL_EC" -ne 0 ]; then
      fail "$label: mutmut results exited $TOOL_EC."
      tool_tail
      return
    fi
    cp "$tmp/tool.out" "$tmp/results.txt" || die "cannot save the mutmut results"
    cut -f2- "$tmp/runs.txt" | awk -F '\t' '{ print $1 "\t" $2 "\t" $3 }' > "$tmp/run.txt"
    "$py" -I "$tmp/helper.py" results "$tmp/results.txt" "$tmp/run.txt" > "$tmp/res.txt" 2> "$tmp/err.txt" || { fail "$label: the python helper stopped: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"; return; }
    report_fails "$tmp/res.txt" "$label"
    local kind a b c
    while IFS="$(printf '\t')" read -r kind a b c; do
      if [ "$kind" = SURVIVOR ]; then
        run_capped "$root" mutmut show "$b"
        cp "$tmp/tool.out" "$tmp/show.txt" || die "cannot save the mutant diff"
        "$py" -I "$tmp/helper.py" diff "$tmp/show.txt" > "$tmp/line.txt" 2> /dev/null || true
        IFS="$(printf '\t')" read -r ln desc < "$tmp/line.txt"
        fail "$label: surviving mutant $b ($c) in ${prefix}$a line ${ln:-?}, changed source ${desc:-unknown}. Add or strengthen a test that fails when this change is made."
        survivors=$((survivors + 1))
      fi
    done < "$tmp/res.txt"
  fi
  checked=$((checked + n))
}

while IFS="$(printf '\t')" read -r tool root; do
  judge_root "$tool" "$root"
done < "$tmp/roots.txt"

if [ "$failed" -eq 1 ]; then
  exit 1
fi
if [ "$checked" -eq 0 ]; then
  echo "check-mutation-diff: nothing checked: no changed source file in mutation scope against $base."
  exit 0
fi
echo "check-mutation-diff: ok ($checked changed source files mutated, no surviving mutant, against $base)"

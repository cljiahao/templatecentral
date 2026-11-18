#!/usr/bin/env bash
# scripts/measure-seeded-load.sh — what a scaffolded project loads into every agent session, and the output caps of its hooks.
#
# Usage: bash scripts/measure-seeded-load.sh [--root DIR]    (DIR: a repo checkout, default this one)
# Scaffolds each stack with tc-copy.sh into a temp folder, then prints one table per stack:
#   CLAUDE.md, AGENTS.md (with the tail), unscoped .claude/rules/**/*.md, files they @import (once each, 4 hops),
#   name+description of every model-invocable
#   skill, and the stdout of session-context.sh for each SessionStart source. Bytes; tokens are an estimate, bytes/4.
# Fails (exit 1) when
#   - a stack's always-loaded bytes (startup source) exceed LOAD_MAX_BYTES (4000, 1,000 tokens; the message names the 3 largest files), or its AGENTS.md exceeds
#     AGENTS_MAX_BYTES (3100: about 2,400 for the stack file plus 700 for the shared tail);
#   - session-context.sh prints more than three lines on compact (the branch line aside) or more than one elsewhere;
#   - a sentence of 8 or more words appears in two always-loaded files;
#   - a hook fixture exceeds its cap: type-check, Stop and SubagentStop output 2,000 chars; comment-check 10 findings
#     of 160 chars plus one "more" line; PreToolUse deny/ask message 200 chars; a silent hook prints anything.
# MEASURE_STACKS="nextjs ..." limits the stacks and MEASURE_HOOKS=0 skips the hook fixtures (the test script uses both to stay fast); the defaults check everything.
# Needs git, node, python3. No network, no keys.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$(cd "${2:-}" && pwd)" || exit 2; shift ;;
    *) echo "measure-seeded-load: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
LOAD_MAX_BYTES=${LOAD_MAX_BYTES:-4000}
AGENTS_MAX_BYTES=${AGENTS_MAX_BYTES:-3100}
COPY="$ROOT/skills/scaffold/shared/tc-copy.sh"
for tool in git node python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "measure-seeded-load: $tool not found" >&2; exit 2; }
done
[[ -f "$COPY" ]] || { echo "measure-seeded-load: $COPY not found" >&2; exit 2; }

W=$(mktemp -d "${TMPDIR:-/tmp}/seedload.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
FAILS=0
fail() { FAILS=$((FAILS + 1)); echo "FAIL: $*"; }

# scaffold <stack> <dir>: the file parts a scaffold copies, plus the one-line CLAUDE.md.
scaffold() {
  local part
  mkdir -p "$2"
  for part in base stack agents settings late tail; do
    TC_STACK=$1 TC_PART=$part bash "$COPY" "$2" >/dev/null 2>&1 || { fail "$1: tc-copy part $part failed"; return 1; }
  done
  printf '@AGENTS.md\n' > "$2/CLAUDE.md"
  git -C "$2" init -q -b main
}

# source_out <dir> <source>: stdout of session-context.sh for one SessionStart source.
source_out() { printf '{"source":"%s"}' "$2" | CLAUDE_PROJECT_DIR="$1" bash "$1/.claude/hooks/session-context.sh" 2>/dev/null; }

# table_and_dups <dir> <stack>: prints the table, fails on a repeated sentence.
table_and_dups() {
  python3 - "$1" "$2" "$LOAD_MAX_BYTES" "$AGENTS_MAX_BYTES" "$W/out.$2" <<'PY'
import glob, os, re, sys
d, stack, load_max, agents_max, outdir = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
def size(p): return os.path.getsize(p) if os.path.exists(p) else 0
def front(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else ""
files = {"CLAUDE.md": open(os.path.join(d, "CLAUDE.md")).read(), "AGENTS.md": open(os.path.join(d, "AGENTS.md")).read()}
sizes = {"CLAUDE.md": size(os.path.join(d, "CLAUDE.md")), "AGENTS.md": size(os.path.join(d, "AGENTS.md"))}
# A rule is path-scoped only when `paths:` carries at least one real pattern; an empty `paths:`, `paths: []` or `paths: ""` loads at launch (fail safe: when in doubt, count it).
def scoped(fm):
    lines = fm.split("\n")
    for i, l in enumerate(lines):
        m = re.match(r"paths:(.*)$", l)
        if not m:
            continue
        if re.sub(r"[\s\[\]\"',]|null|~", "", m.group(1)):
            return True
        for x in lines[i + 1:]:
            if x.strip() and not re.match(r"\s|-", x):
                break
            m = re.match(r"\s*-(.*)$", x)
            if m and re.sub(r"[\s\"']", "", m.group(1)).strip("#") and not m.group(1).strip().startswith("#"):
                return True
        return False
    return False
rules = 0
for p in sorted(glob.glob(os.path.join(d, ".claude/rules/**/*.md"), recursive=True)):
    t = open(p).read()
    if not scoped(front(t)):
        files[os.path.relpath(p, d)] = t
        sizes[os.path.relpath(p, d)] = len(t.encode())
        rules += len(t.encode())
# Follow @path imports from CLAUDE.md and AGENTS.md: each file once, relative to the importer, at most 4 hops (docs, code.claude.com/docs/en/memory: \"Imported files can recursively import other files, with a maximum depth of four hops.\"). AGENTS.md's own imports start at hop 1 here, one hop more generous than the docs: a deliberate over-count.
def imports_of(text):
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    text = re.sub(r"`[^`\n]*`", "", text)
    return re.findall(r"(?<!\S)@([^\s@]+)", text)
imported = 0
seen_files = {os.path.realpath(os.path.join(d, n)) for n in ("CLAUDE.md", "AGENTS.md")}
queue = [(os.path.join(d, n), 0) for n in ("CLAUDE.md", "AGENTS.md")]
while queue:
    src, depth = queue.pop(0)
    if depth >= 4:
        continue
    for ref in imports_of(open(src).read()):
        p = os.path.realpath(os.path.join(os.path.dirname(src), os.path.expanduser(ref)))
        if p in seen_files or not os.path.isfile(p):
            continue
        seen_files.add(p)
        t = open(p).read()
        files[os.path.relpath(p, d)] = t
        sizes[os.path.relpath(p, d)] = len(t.encode())
        imported += len(t.encode())
        queue.append((p, depth + 1))
skills = 0
for p in sorted(glob.glob(os.path.join(d, ".claude/skills/*/SKILL.md"))):
    fm = front(open(p).read())
    if re.search(r"^disable-model-invocation:\s*true", fm, re.M):
        continue
    keep = [l for l in fm.split("\n") if l.startswith(("name:", "description:"))]
    skills += len("\n".join(keep).encode()) + 1
    sizes[os.path.relpath(p, d)] = len("\n".join(keep).encode()) + 1
    desc = next((l[len("description:"):].strip() for l in keep if l.startswith("description:")), "")
    files[os.path.relpath(p, d)] = desc
out = {s: open(os.path.join(outdir, s)).read() for s in ("startup", "resume", "clear", "compact")}
claude, agents = size(os.path.join(d, "CLAUDE.md")), size(os.path.join(d, "AGENTS.md"))
startup = len(out["startup"].encode())
sizes["session-context.sh startup output"] = startup
total = claude + agents + rules + imported + skills + startup
row = "%-11s CLAUDE %4d  AGENTS %5d  rules %4d  imports %4d  skills %4d  session start/resume/clear/compact %d/%d/%d/%d  total %5d bytes = est. %4d tokens (bytes/4)"
print(row % (stack, claude, agents, rules, imported, skills, startup, len(out["resume"].encode()), len(out["clear"].encode()), len(out["compact"].encode()), total, total // 4))
bad = 0
def fail(m):
    global bad; bad += 1; print("FAIL: %s: %s" % (stack, m))
top = ", ".join("%s %d" % kv for kv in sorted(sizes.items(), key=lambda kv: -kv[1])[:3])
if total > load_max: fail("always-loaded %d bytes exceeds %d; largest: %s" % (total, load_max, top))
if agents > agents_max: fail("AGENTS.md %d bytes exceeds %d" % (agents, agents_max))
for s in ("startup", "resume", "clear"):
    if len([l for l in out[s].split("\n") if l]) > 1: fail("session-context.sh prints more than one line on %s" % s)
if len([l for l in out["compact"].split("\n") if l]) > 4: fail("session-context.sh prints more than a branch line plus three lines on compact")
seen = {}
for name, text in files.items():
    for part in re.split(r"(?<=[.!?])\s+|\n+", text):
        words = re.sub(r"[^a-z0-9 ]+", "", re.sub(r"^[\s>*#|`-]+", "", part).lower()).split()
        if len(words) >= 8:
            seen.setdefault(" ".join(words), set()).add(name)
for sent, names in sorted(seen.items()):
    if len(names) > 1: fail("sentence in %s: \"%s\"" % (" and ".join(sorted(names)), sent[:70]))
sys.exit(1 if bad else 0)
PY
}

# ── Hook fixtures ─────────────────────────────────────────────────────────────

# make_stubs <dir>: pnpm and python stubs that pass probes and fail every real step with 60 long lines.
make_stubs() {
  mkdir -p "$1"
  cat > "$1/pnpm" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "exec tsc --version" | "exec vitest --version") exit 0 ;;
esac
i=0; while [ "$i" -lt 60 ]; do i=$((i + 1)); printf 'src/a.ts(%d,7): error TS2322: Type "string" is not assignable to type "number" %0200d\n' "$i" 0; done
exit 1
STUB
  cat > "$1/python" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "-m pyright --version" | "-m pytest --version") exit 0 ;;
esac
i=0; while [ "$i" -lt 60 ]; do i=$((i + 1)); printf '/p/src/a.py:%d:5 - error: "x" is not defined (reportUndefinedVariable) %0200d\n' "$i" 0; done
exit 1
STUB
  chmod +x "$1/pnpm" "$1/python"
}

# json_field <key>: length of that hookSpecificOutput field in the JSON on stdin.
json_field() {
  python3 -c 'import json, sys; d = json.load(sys.stdin)["hookSpecificOutput"]; print(len(d[sys.argv[1]]))' "$1" 2>/dev/null
}

# hook_fixtures <stack> <dir> <ext>: run every capped hook against an over-cap fixture.
hook_fixtures() {
  local stack=$1 dir=$2 ext=$3 proj="$W/proj.$1" n out ec file
  rm -rf "$proj"; cp -R "$dir" "$proj"
  git -C "$proj" add -A >/dev/null 2>&1
  git -C "$proj" -c user.email=t@example.com -c user.name=t commit -q -m seed >/dev/null 2>&1
  mkdir -p "$proj/src"
  file="src/a.$ext"
  python3 - "$proj/$file" "$ext" <<'PY'
import sys
c = "//" if sys.argv[2] == "ts" else "#"
open(sys.argv[1], "w").write("".join("%s Added retry loop number %d for the new feature %s\nx%d = 1\n" % (c, i, "z" * 150, i) for i in range(40)))
PY
  local stubs="$W/stubs"; make_stubs "$stubs"
  local hooks="$proj/.claude/hooks" env=(env "PATH=$stubs:$PATH" "CLAUDE_PROJECT_DIR=$proj")

  out=$(printf '{"tool_input":{"file_path":"%s"}}' "$file" | (cd / && "${env[@]}" bash "$hooks/post-edit-typecheck.sh") 2>/dev/null)
  n=$(printf '%s' "$out" | json_field additionalContext)
  [[ -n "$n" && "$n" -le 2000 ]] || fail "$stack: post-edit-typecheck.sh emitted ${n:-no} chars (cap 2000)"
  [[ "$out" == *"more lines not shown"* ]] || fail "$stack: post-edit-typecheck.sh did not name the dropped lines"

  out=$(printf '{"tool_input":{"file_path":"%s"}}' "$file" | (cd / && "${env[@]}" bash "$hooks/post-edit-comment-check.sh") 2>/dev/null)
  n=$(printf '%s' "$out" | json_field additionalContext)
  local lines longest
  lines=$(printf '%s' "$out" | python3 -c 'import json, sys; print(len(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"].split("\n")))' 2>/dev/null)
  longest=$(printf '%s' "$out" | python3 -c 'import json, sys; print(max(len(l) for l in json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"].split("\n")[1:]))' 2>/dev/null)
  [[ -n "$lines" && "$lines" -le 12 && "${longest:-999}" -le 175 ]] || fail "$stack: post-edit-comment-check.sh emitted ${lines:-no} lines, longest ${longest:-?} chars (cap 10 findings of 160 plus a count line)"
  [[ "$out" == *"more findings"* ]] || fail "$stack: post-edit-comment-check.sh did not name the dropped findings"

  local hook err
  for hook in stop-checks subagent-stop; do
    err=$(printf '{"agent_type":"general-purpose"}' | (cd / && "${env[@]}" bash "$hooks/$hook.sh") 2>&1 >/dev/null); ec=$?
    [[ "$ec" -eq 2 ]] || fail "$stack: $hook.sh exited $ec on a failing check (want 2)"
    [[ "${#err}" -le 2000 ]] || fail "$stack: $hook.sh printed ${#err} chars (cap 2000)"
    [[ "$err" == *"more lines not shown"* ]] || fail "$stack: $hook.sh did not name the dropped lines"
  done

  local deep
  deep=$(printf 'd%.0s' $(seq 1 120))
  out=$(tool_json=$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": sys.argv[1]}}))' "$deep/.claude/settings.json"); printf '%s' "$tool_json" | (cd / && "${env[@]}" bash "$hooks/protect-files.sh") 2>/dev/null)
  n=$(printf '%s' "$out" | json_field permissionDecisionReason)
  [[ -n "$n" && "$n" -le 200 ]] || fail "$stack: protect-files.sh ask message is ${n:-missing} chars (cap 200)"

  local cmd
  for cmd in "git -c core.hooksPath=/dev/null commit -m x" "git push --force-with-lease origin main" "git checkout -- .claude/settings.json" "rm -rf src" "git commit -n -m x"; do
    err=$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$cmd" | (cd / && "${env[@]}" bash "$hooks/block-no-verify.sh") 2>&1 >/dev/null); ec=$?
    [[ "${#err}" -le 200 ]] || fail "$stack: block-no-verify.sh message for '$cmd' is ${#err} chars (cap 200)"
  done

  # Silence on success: a clean tree and a passing check print nothing.
  git -C "$proj" checkout -q -- . 2>/dev/null; rm -f "$proj/$file"
  err=$(printf '{}' | (cd / && "${env[@]}" bash "$hooks/stop-checks.sh") 2>&1); ec=$?
  [[ "$ec" -eq 0 && -z "$err" ]] || fail "$stack: stop-checks.sh is not silent on a clean tree (exit $ec)"
  out=$(printf '{"tool_input":{"file_path":"README.md"}}' | (cd / && "${env[@]}" bash "$hooks/post-edit-typecheck.sh") 2>&1)
  [[ -z "$out" ]] || fail "$stack: post-edit-typecheck.sh is not silent on an unrelated file"
}

for stack in ${MEASURE_STACKS:-nextjs vite-react fastapi nestjs}; do
  dir="$W/$stack"
  scaffold "$stack" "$dir" || continue
  mkdir -p "$W/out.$stack"
  for s in startup resume clear compact; do source_out "$dir" "$s" > "$W/out.$stack/$s"; done
  table_and_dups "$dir" "$stack" || FAILS=$((FAILS + 1))
  ext=ts; [[ "$stack" == fastapi ]] && ext=py
  [[ "${MEASURE_HOOKS:-1}" == 0 ]] || hook_fixtures "$stack" "$dir" "$ext"
done

if [[ "$FAILS" -gt 0 ]]; then echo "measure-seeded-load: $FAILS failure(s)"; exit 1; fi
echo "measure-seeded-load: all stacks within budget"

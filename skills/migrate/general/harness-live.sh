#!/usr/bin/env bash
# Harness live check: prove the seeded harness is wired and fires in a project, not only present. It never writes to the project.
# Usage: harness-live.sh <project-dir>
# Prints PASS or FAIL per item; exits 1 when any item fails, 2 on a usage error. It reads no environment or key file.
# Needs bash 3.2+, git, and python3 or node to read .claude/settings.json.
set -u

[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: harness-live.sh <project-dir>" >&2; exit 2; }
P=$(cd "$1" && pwd -P) || exit 2

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a tool from the project first, then PATH.
resolve() {
  local d
  for d in node_modules/.bin .venv/bin; do
    [ -x "$P/$d/$1" ] && { echo "$P/$d/$1"; return 0; }
  done
  command -v "$1"
}

# settings_hooks: a "__disable__ <true|false>" line, then one "<event> <command> <first-arg>" line per registered hook; command is ARRAY when not a string.
settings_hooks() {
  if have python3; then
    python3 - "${1:-$P/.claude/settings.json}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("__disable__", str(d.get("disableAllHooks", False)).lower(), "")
for ev, groups in d.get("hooks", {}).items():
    for g in groups:
        for h in g.get("hooks", []):
            c = h.get("command"); a = h.get("args") or [""]
            print(ev, c if isinstance(c, str) else "ARRAY", a[0])
PY
  elif have node; then
    node - "${1:-$P/.claude/settings.json}" <<'JS'
const d = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
console.log("__disable__", String(d.disableAllHooks === true), "");
for (const [ev, groups] of Object.entries(d.hooks || {}))
  for (const g of groups) for (const h of g.hooks || []) {
    const a = h.args && h.args.length ? h.args[0] : "";
    console.log(ev, typeof h.command === "string" ? h.command : "ARRAY", a);
  }
JS
  else return 3; fi
}

# section_lines <file> <key>: the non-comment lines of one top-level section of a YAML file.
section_lines() { awk -v k="$2" '/^[^[:space:]#]/ { on = ($0 ~ "^" k ":") } on && !/^[[:space:]]*#/' "$1"; }

# gitleaks_state <file>: ok, skip or none for gitleaks invoked on a run line of a pre-commit command that is not skipped.
gitleaks_state() {
  section_lines "$1" pre-commit | awk '
    function check(v) { if (v ~ /(^|[;&|(]|then|do|else)[ \t]*([A-Za-z_][A-Za-z0-9_]*=[^ \t]+[ \t]+)*([^ \t]*\/)?gitleaks[ \t]+(git|detect|protect|dir|stdin)/) has[cmd] = 1 }
    /^  skip:[ \t]*true/ { hookskip = 1 }
    /^    [A-Za-z0-9_-]+:[ \t]*$/ { cmd = $1; inrun = 0; next }
    inrun && match($0, /[^ \t]/) && RSTART > 7 { check($0); next }
    { inrun = 0 }
    /^      skip:[ \t]*true/ { sk[cmd] = 1 }
    /^      run:/ { v = $0; sub(/^[ \t]*run:[ \t]*/, "", v); if (v ~ /^[|>][-+]?[ \t]*$/) inrun = 1; else { sub(/^["\047]/, "", v); check(v) } }
    END { for (k in has) { if (!sk[k] && !hookskip) found = 1; else skipped = 1 } print found ? "ok" : (skipped ? "skip" : "none") }'
}

# hook_runs_lefthook <file>: a git hook that runs lefthook on a line outside a comment, with no top-level exit before it.
hook_runs_lefthook() {
  sed -E 's/[[:space:]]#.*$//' "$1" | awk '
    /^[ \t]*(#|echo|printf|:)/ { next }
    {
      l = $0; tmp = l; o = gsub(/(^|[^A-Za-z0-9_])(if|case|while|for|until)[ \t]/, "&", tmp)
      tmp = l; cl = gsub(/(^|[^A-Za-z0-9_])(fi|esac|done)([^A-Za-z0-9_]|$)/, "&", tmp)
      if (l ~ /^[ \t]*\{[ \t]*$/ || l ~ /\)[ \t]*\{[ \t]*$/) o++
      if (l ~ /^[ \t]*\}[ \t]*$/) cl++
      if (d == 0 && l ~ /^[ \t]*exit([ \t]+[0-9]+)?[ \t]*(;.*)?$/) exited = 1
      if (!exited && l ~ /(lefthook|LEFTHOOK_BIN"?|call_lefthook)[ \t]+(run|hook)/) ok = 1
      d += o - cl
    }
    END { exit !ok }'
}

# 1. lefthook binary, config and wired git hooks
lh=$(resolve lefthook)
if [ -n "$lh" ]; then pass "lefthook binary ($lh)"; else fail "lefthook binary" "not in node_modules/.bin, .venv/bin or PATH"; fi
if [ -f "$P/lefthook.yml" ]; then
  for h in pre-commit pre-push; do
    if section_lines "$P/lefthook.yml" "$h" | grep -Eq '^[[:space:]]+commands:' && section_lines "$P/lefthook.yml" "$h" | grep -Eq '^[[:space:]]{4}[A-Za-z0-9_-]+:'; then pass "lefthook.yml $h defines commands"
    else fail "lefthook.yml $h" "no $h section with a non-empty commands block"; fi
  done
  case "$(gitleaks_state "$P/lefthook.yml")" in
    ok) pass "lefthook.yml pre-commit runs gitleaks" ;;
    skip) fail "lefthook.yml gitleaks" "the gitleaks command or the pre-commit hook sets skip: true" ;;
    *) fail "lefthook.yml gitleaks" "no run line in pre-commit invokes gitleaks (git, detect, protect, dir or stdin) outside a comment" ;;
  esac
  if git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    hooks_dir=$(git -C "$P" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)
    for h in pre-commit commit-msg pre-push; do
      grep -Eq "^$h:" "$P/lefthook.yml" || continue
      if [ -f "$hooks_dir/$h" ] && [ -x "$hooks_dir/$h" ] && hook_runs_lefthook "$hooks_dir/$h"; then pass "git hook $h executable and calls lefthook"
      else fail "git hook $h" "lefthook.yml defines it but $hooks_dir/$h is missing, not executable, or does not run lefthook before any top-level exit; run lefthook install"; fi
    done
  else fail "git hooks" "not a git repository"; fi
else fail "lefthook.yml" "missing"; fi

# 2. gitleaks and its config
gl=$(resolve gitleaks)
if [ -n "$gl" ]; then pass "gitleaks binary ($gl)"; else fail "gitleaks binary" "not resolvable; install it"; fi
if [ -f "$P/.gitleaks.toml" ]; then pass ".gitleaks.toml present"; else fail ".gitleaks.toml" "missing"; fi

# 3. agent hooks: seeded, executable when run as scripts, registered under the right event in settings.json in exec form
# fire <hook-file> <payload>: run a guard in the project on a synthetic payload; prints "<exit status> <stderr>". The guards only read.
fire() {
  local out rc
  case "$1" in
    *.sh) out=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$1" 2>&1 >/dev/null <<<"$2"); rc=$? ;;
    *.py) out=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$1" 2>&1 >/dev/null <<<"$2"); rc=$? ;;
    *) out=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" node "$1" 2>&1 >/dev/null <<<"$2"); rc=$? ;;
  esac
  echo "$rc $out"
}
if [ -f "$P/.claude/settings.json" ]; then
  reg=$(settings_hooks) || reg=FAILED
  if [ "$reg" = FAILED ]; then fail ".claude/settings.json" "unreadable, or neither python3 nor node is available"; reg=; fi
  if printf '%s\n' "$reg" | grep -q '^__disable__ true'; then fail "settings.json disableAllHooks" "true turns every hook off"; fi
  if printf '%s\n' "$reg" | grep -q ' ARRAY '; then fail "settings.json hooks" "an array-valued command never runs; use exec form (command + args)"; fi
  for pair in protect-files:PreToolUse block-no-verify:PreToolUse user-prompt-guard:UserPromptSubmit post-edit-typecheck:PostToolUse post-edit-comment-check:PostToolUse stop-checks:Stop subagent-stop:SubagentStop session-context:SessionStart skill-usage-log:PostToolUse; do
    name=${pair%%:*}; event=${pair#*:}
    file=$(find "$P/.claude/hooks" -maxdepth 1 -name "$name.*" 2>/dev/null | head -1)
    if [ -z "$file" ]; then fail "hook $name" "script missing under .claude/hooks"; continue; fi
    case "$file" in
      *.sh) [ -x "$file" ] || { fail "hook $name" "$(basename "$file") is not executable"; continue; } ;;
    esac
    want="/.claude/hooks/$(basename "$file")"
    if printf '%s\n' "$reg" | awk -v w="$want" -v e="$event" '$1 == e { n = length($NF) - length(w) + 1; if (n > 0 && substr($NF, n) == w) f = 1 } END { exit !f }'; then pass "hook $name executable and registered under $event"
    else fail "hook $name" "not registered under $event in .claude/settings.json"; fi
  done
else fail ".claude/settings.json" "missing"; fi
if [ -f "$P/.claude/settings.local.json" ]; then
  if ! loc=$(settings_hooks "$P/.claude/settings.local.json" 2>/dev/null); then fail "settings.local.json" "unreadable or not valid JSON"
  elif printf '%s\n' "$loc" | grep -q '^__disable__ true'; then fail "settings.local.json disableAllHooks" "true turns every hook off"
  else pass "settings.local.json does not disable hooks"; fi
fi

# 3b. fire the two blocking guards on a synthetic payload; a no-op script passes the checks above but not this
guard_file() { find "$P/.claude/hooks" -maxdepth 1 -name "$1.*" 2>/dev/null | head -1; }
gf=$(guard_file protect-files)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Write","tool_input":{"file_path":".env","content":"x"}}') # PAYLOAD: synthetic, never read
  if [ "${r%% *}" = 2 ] && [[ "$r" == *BLOCKED* ]]; then pass "protect-files blocks a write to an environment file"; else fail "protect-files guard" "a synthetic secret write was not blocked (exit ${r%% *})"; fi
fi
gf=$(guard_file block-no-verify)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}')
  if [ "${r%% *}" = 2 ] && [[ "$r" == *BLOCKED* ]]; then pass "block-no-verify blocks git commit --no-verify"; else fail "block-no-verify guard" "a synthetic --no-verify commit was not blocked (exit ${r%% *})"; fi
fi

# 3b2. each guard also lets a benign payload through, so a hook that always blocks does not pass
gf=$(guard_file protect-files)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Write","tool_input":{"file_path":"src/x.txt","content":"x"}}')
  if [ "${r%% *}" = 0 ]; then pass "protect-files allows an ordinary write"; else fail "protect-files guard" "an ordinary write was blocked (exit ${r%% *})"; fi
fi
gf=$(guard_file block-no-verify)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
  if [ "${r%% *}" = 0 ]; then pass "block-no-verify allows git status"; else fail "block-no-verify guard" "git status was blocked (exit ${r%% *})"; fi
fi
echo "NOTE: the other hooks are not fired; their content is covered by the .claude/verify-harness.sh hash check below."

# 3c. integrity: seeded guard files still hash to their origin, which also catches a hook replaced by a no-op
if [ -f "$P/.claude/verify-harness.sh" ]; then
  if vout=$(cd "$P" && bash .claude/verify-harness.sh 2>&1); then pass "verify-harness.sh: enforcement files match their origin hashes"
  else fail "verify-harness.sh" "$(printf '%s' "$vout" | tr '\n' ' ' | cut -c1-200)"; fi
else fail ".claude/verify-harness.sh" "missing"; fi

# 4. CI workflow runs the gates
ci=()
for f in "$P"/.github/workflows/*.yml "$P"/.github/workflows/*.yaml "$P"/azure-pipelines.yml "$P"/azure-pipelines/*.yml; do
  [ -f "$f" ] && ci+=("$f")
done
if [ "${#ci[@]}" -eq 0 ]; then fail "CI workflow" "no .github/workflows or azure-pipelines file"
else
  if grep -hv '^[[:space:]]*#' "${ci[@]}" | grep -q 'ci-gates.sh'; then pass "CI runs .claude/ci-gates.sh"; else fail "CI gates" "no workflow line outside a comment runs .claude/ci-gates.sh"; fi
  if grep -hv '^[[:space:]]*#' "${ci[@]}" | grep -q 'verify-harness.sh'; then pass "CI runs .claude/verify-harness.sh"; else fail "CI harness check" "no workflow line outside a comment runs .claude/verify-harness.sh"; fi
fi
[ -f "$P/.claude/ci-gates.sh" ] || fail ".claude/ci-gates.sh" "missing"

if [ "$FAILS" -gt 0 ]; then echo "FAIL: $FAILS item(s) not live."; exit 1; fi
echo "OK: harness is live."

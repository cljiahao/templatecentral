<!-- ref: scaffold/shared/harness-kit-fastapi.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/fastapi/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified as FastAPI; harness-kit.md (index + delta table) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — FastAPI bodies

Per-stack bodies for kit Steps A, B, B2, and B3 (FastAPI). Write each where `harness-kit-enforcement.md` reaches that step. The other stack's bodies live in `harness-kit-ts.md` — do not load it.

---

## Step A — `.claude/settings.json` (FastAPI)

**`.claude/settings.json`** (substitute runtime from delta table for `user-prompt-guard`):

**For FastAPI:** identical shape; `UserPromptSubmit` runs `python3` on `user-prompt-guard.py` and the typecheck/test scripts use `pyright`/`pytest`:
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(**/.env)",
      "Read(**/.env.local)",
      "Read(**/.env.*.local)",
      "Read(**/.env.development)",
      "Read(**/.env.production)",
      "Read(**/.env.staging)",
      "Read(**/.env.test)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(./secrets/**)",
      "Read(./.secrets/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/protect-files.sh"], "timeout": 10 }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/block-no-verify.sh"], "timeout": 10 }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "python3", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/user-prompt-guard.py"], "timeout": 10 }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/post-edit-typecheck.sh"], "timeout": 60 }]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/post-edit-comment-check.sh"], "timeout": 30 }]
      },
      {
        "matcher": "Skill",
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/skill-usage-log.sh"], "timeout": 10 }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/stop-checks.sh"], "timeout": 300 }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/subagent-stop.sh"], "timeout": 120 }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command", "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/session-context.sh"], "timeout": 10 }]
      }
    ]
  },
  "skillListingBudgetFraction": 0.02
}
```

---

## Step B — hook scripts (FastAPI)

**`.claude/hooks/protect-files.sh`** (canonical — strongest variant, adopted from NestJS; blocks `secrets/*` and `.secrets/*` hard):

**For FastAPI — uses `python3` for JSON parsing:**
```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) — protect secrets, CI, cert, and governance files.
# Exit 2 = hard block (stderr → model); permissionDecision "ask" JSON (exit 0) = require human approval; plain exit 0 = allow.
# Fail closed: a guard that cannot locate the project root blocks rather than guessing.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: protect-files.sh cannot cd to the project root — refusing the write." >&2; exit 2; }
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('notebook_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
[ -z "$file" ] && exit 0
shopt -s nocasematch   # .ENV, Dockerfile vs dockerfile, AGENTS.md vs agents.md — case-insensitive filesystems make these the same file
while [[ "$file" == ./* ]]; do file="${file#./}"; done
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $base is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

# Resolve to a project-relative path: physical root (pwd -P — macOS /tmp is really /private/tmp),
# relative paths anchored at the root, the longest existing ancestor canonicalised (symlinked
# parents), and `.`/`..` in the not-yet-existing remainder folded lexically — so neither
# `src/../.github/…` (no src/) nor a symlinked parent can disguise the target.
root=$(pwd -P)
case "$file" in /*) abs="$file" ;; *) abs="$root/$file" ;; esac
canon() {
  local d="${1%/*}" r="" n="" s p
  while [ -n "$d" ] && [ ! -d "$d" ]; do r="/${d##*/}$r"; d="${d%/*}"; done
  p=$(cd "${d:-/}" 2>/dev/null && pwd -P) && d="$p"
  r="${r#/}"
  while [ -n "$r" ]; do
    s="${r%%/*}"; case "$r" in */*) r="${r#*/}" ;; *) r="" ;; esac
    case "$s" in ""|.) ;; ..) if [ -n "$n" ]; then n="${n%/*}"; else d="${d%/*}"; fi ;; *) n="$n/$s" ;; esac
  done
  printf '%s' "${d%/}$n/${1##*/}"
}
abs=$(canon "$abs"); abs=$(canon "$abs")   # 2nd pass: the folded path may now cross an existing (symlinked) dir
rel="${abs#"$root"/}"

if [[ "$rel" == .github/workflows/* || "$rel" == .github/actions/* || "$rel" == .azuredevops/* \
   || "$base" == azure-pipelines*.yml || "$base" == azure-pipelines*.yaml \
   || "$base" == ".gitlab-ci.yml" || "$base" == "Jenkinsfile" ]]; then
  echo "BLOCKED: $rel is a CI/CD pipeline definition (GitHub / Azure DevOps / GitLab / Jenkins) — requires human review." >&2
  exit 2
elif [[ "$rel" == secrets/* || "$rel" == .secrets/* ]]; then
  echo "BLOCKED: $rel is inside a secrets directory — must never be written by the agent." >&2
  exit 2
elif [[ "$base" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $rel is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md|*/docs/CONSTITUTION.md) reason="binding invariants document — changes affect all agents and this project's behaviour" ;;
  .claude/settings.json|*/.claude/settings.json|.claude/settings.local.json|*/.claude/settings.local.json) reason="harness config — editing it can silently disable every hook or add permissive perms (settings.local.json takes precedence over settings.json)" ;;
  .claude/hooks/*|*/.claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  .claude/agents/*|*/.claude/agents/*) reason="agent definition — editing it can alter subagent tool access/behavior" ;;
  .mcp.json|*/.mcp.json) reason="MCP server config — editing it can register a malicious/exfiltrating server" ;;
  .claude/harness.json|*/.claude/harness.json|.claude/verify-harness.sh|*/.claude/verify-harness.sh|.claude/regen-harness.sh|*/.claude/regen-harness.sh) reason="harness integrity baseline/verifier — editing it can defeat drift detection" ;;
  .claude/.harness-base/*|*/.claude/.harness-base/*) reason="merge base snapshot — editing it can poison harness re-sync merges" ;;
  Dockerfile|*/Dockerfile) reason="container image definition" ;;
  lefthook.yml|*/lefthook.yml|.gitleaks.toml|*/.gitleaks.toml) reason="git-hook enforcement config — editing it can weaken commit-time guards" ;;
  .claude/comment-hygiene-patterns.txt|*/.claude/comment-hygiene-patterns.txt) reason="comment-hygiene enforcement pattern list — editing it can silently weaken the CI hard gate" ;;
  .lefthook/*|*/.lefthook/*) reason="git-hook script — editing it can weaken commit-time guards" ;;
esac
if [ -n "$reason" ]; then
  # Emit permissionDecision "ask" so Claude Code prompts for human approval before the write.
  # (`exit 1` + stderr is NON-blocking on PreToolUse — the edit goes through and the warning
  # never reaches the model. Only "ask" actually gates the write.) JSON is built by the runtime,
  # never by printf, so a path containing quotes/backslashes can't break or inject into it.
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"PROTECTED FILE: "+sys.argv[1]+" — "+sys.argv[2]+". Confirm human approval and note it in the PR."}}))' "$rel" "$reason" \
    || { echo "BLOCKED: $rel is protected ($reason) and the approval prompt could not be built." >&2; exit 2; }
  exit 0
fi
exit 0
```

---

**`.claude/hooks/block-no-verify.sh`** (runtime varies for JSON parsing only; logic is identical):

**For FastAPI — uses `python3`:**
```bash
#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
# Best-effort tripwire, not a security boundary: a determined shell can always obfuscate.
# The lefthook + CI layers are the backstop.
orig_dir=$PWD   # Claude's current directory — used to resolve the branch a bare `git commit` targets
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: block-no-verify.sh cannot cd to the project root — refusing the command." >&2; exit 2; }
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)
[ -z "$cmd" ] && exit 0
# Drop heredoc bodies (a commit message saying "git push --force origin main" is text, not a command):
# from a line opening `<<WORD` / `<<-'WORD'` / `<<"WORD"` (not the `<<<` here-string) through the
# line equal to WORD (leading tabs allowed for `<<-`). The opening line itself is still scanned.
cmd=$(printf '%s\n' "$cmd" | awk '
  inh { t = $0; if (tabs) sub(/^\t+/, "", t); if (t == w) inh = 0; next }
  { print; l = $0; gsub(/<<</, "", l)
    if (match(l, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
      w = substr(l, RSTART, RLENGTH); tabs = (w ~ /^<<-/); sub(/^<<-?[[:space:]]*["\047]?/, "", w); inh = 1 } }')
block() { echo "BLOCKED: $1" >&2; exit 2; }
# Branch a bare commit/push targets: Claude's cwd first, else the project root.
cur_branch() { git -C "$orig_dir" ${cdir:+-C "$cdir"} rev-parse --abbrev-ref HEAD 2>/dev/null || git ${cdir:+-C "$cdir"} rev-parse --abbrev-ref HEAD 2>/dev/null; }
protected='main|uat|develop'

# Normalise before flag-matching:
#  1. unwrap `bash|sh|zsh -c "…"` / `eval "…"` so a wrapped command is scanned, not scrubbed away;
#  2. unquote quoted single words ("--no-verify", "main") — the shell strips those quotes too;
#  3. replace remaining (multi-word) quoted strings with a placeholder (Q) so text inside
#     -m "…" can't false-trigger. Double quotes are handled before single quotes so an
#     apostrophe inside "it's done" can't pair with a later ' and swallow real flags.
sq="'"
scan=$(printf '%s' "$cmd" | sed -E \
  -e "s/(^|[[:space:];&|(])(bash|sh|zsh|eval)([[:space:]]+-[a-z]*c)?[[:space:]]+\"([^\"]*)\"/\1 \4 /g" \
  -e "s/(^|[[:space:];&|(])(bash|sh|zsh|eval)([[:space:]]+-[a-z]*c)?[[:space:]]+${sq}([^${sq}]*)${sq}/\1 \4 /g" \
  -e "s/\"([^\"${sq}[:space:]]*)\"/\1/g" -e "s/\"[^\"]*\"/ Q /g" \
  -e "s/${sq}([^${sq}[:space:]]*)${sq}/\1/g" -e "s/${sq}[^${sq}]*${sq}/ Q /g")

# Hook-layer bypass via environment or a persisted alias/config (whole-command checks).
lower_cmd=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
if printf '%s' "$scan" | grep -qE '(^|[^A-Za-z0-9_])LEFTHOOK(_EXCLUDE)?=' && printf '%s' "$scan" | grep -qE '(^|[^A-Za-z0-9_-])git([[:space:]]|$)'; then
  block "LEFTHOOK=0 / LEFTHOOK_EXCLUDE disables the pre-commit hook layer — the same bypass as --no-verify. Fix the failure instead."
fi
if printf '%s' "$lower_cmd" | grep -qE 'git_config_(parameters|key_[0-9]+)' && printf '%s' "$lower_cmd" | grep -q 'hookspath'; then
  block "GIT_CONFIG_* overriding core.hooksPath disables the git-hook layer. Fix the failure instead."
fi
if printf '%s' "$lower_cmd" | grep -q 'alias\.' && printf '%s' "$lower_cmd" | grep -q 'no-verify'; then
  block "a git alias wrapping --no-verify is the same bypass as --no-verify. Fix the failure instead."
fi

# Evaluate each simple command separately: split on && || ; | & ( ) ` and newlines.
segments=$(printf '%s\n' "$scan" | tr ';|&()`' '\n\n\n\n\n\n')
while IFS= read -r seg; do
  read -ra t <<< "$seg"
  n=${#t[@]}; i=0
  while [ "$i" -lt "$n" ]; do              # locate the git executable (git, /usr/bin/git, \git)
    w="${t[$i]#\\}"
    [[ "$w" == git || "$w" == */git ]] && break
    i=$((i + 1))
  done
  [ "$i" -ge "$n" ] && continue
  i=$((i + 1)); cdir=""
  while [ "$i" -lt "$n" ] && [[ "${t[$i]}" == -* ]]; do   # git global options precede the subcommand
    o="${t[$i]}"
    case "$o" in
      -C) cdir="${t[$((i + 1))]:-}"; i=$((i + 2)); continue ;;
      -c|--config-env)
        printf '%s' "${t[$((i + 1))]:-}" | grep -qi 'core\.hookspath' && block "'git -c core.hooksPath=…' disables the git-hook layer — the same bypass as --no-verify. Fix the failure instead."
        i=$((i + 2)); continue ;;
      --git-dir|--work-tree|--namespace|--exec-path|--super-prefix) i=$((i + 2)); continue ;;
    esac
    printf '%s' "$o" | grep -qi 'core\.hookspath' && block "overriding core.hooksPath disables the git-hook layer. Fix the failure instead."
    i=$((i + 1))
  done
  sub="${t[$i]:-}"; i=$((i + 1))
  args=("${t[@]:$i}")

  case "$sub" in
    commit|push|merge|am|rebase|cherry-pick|revert|pull)
      for a in "${args[@]}"; do
        [ "$a" = "--" ] && break
        [[ "$a" == --no-veri* ]] && block "--no-verify on 'git $sub' bypasses the git hooks. Fix the failure instead."
      done ;;
  esac

  case "$sub" in
    commit)
      skip=0
      for a in "${args[@]}"; do
        [ "$a" = "--" ] && break
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$a" in
          --*) ;;
          -?*)   # short-flag cluster: walk letters; a value-taking flag consumes the rest (or the next word)
            f="${a#-}"
            while [ -n "$f" ]; do
              c="${f:0:1}"; f="${f:1}"
              case "$c" in
                n) block "-n (--no-verify) on git commit bypasses the pre-commit hooks. Fix the failure instead." ;;
                m|F|c|C|t|S|u) [ -z "$f" ] && [ "$c" != "S" ] && [ "$c" != "u" ] && skip=1; break ;;
              esac
            done ;;
        esac
      done
      branch=$(cur_branch)
      [[ "$branch" =~ ^($protected)$ ]] && block "direct commit to protected branch '$branch'. Create a feature branch first."
      ;;
    push)
      force=0; target=0; explicit=0; pos=0
      for a in "${args[@]}"; do
        case "$a" in
          --force|--force=*|--force-with-lease|--force-with-lease=*|--force-if-includes|--mirror) force=1 ;;
          --delete) force=1 ;;
          --*) ;;
          -*) [[ "${a#-}" == *[fd]* ]] && force=1 ;;
          *)
            pos=$((pos + 1))
            [ "$pos" -eq 1 ] && continue   # first positional is the remote
            explicit=1
            [[ "$a" == +* || "$a" == :* ]] && force=1   # +refspec forces; :branch deletes
            [[ "$a" =~ ^\+?((refs/heads/)?($protected)|[^:]*:(refs/heads/)?($protected))$ ]] && target=1
            # `HEAD` / `@` (no `:dst`) pushes the current branch to its same-named remote branch
            if [[ "$a" =~ ^\+?(HEAD|@)$ ]]; then branch=$(cur_branch); [[ "$branch" =~ ^($protected)$ ]] && target=1; fi ;;
        esac
      done
      if [ "$explicit" -eq 0 ]; then
        branch=$(cur_branch)
        [[ "$branch" =~ ^($protected)$ ]] && target=1
      fi
      [ "$force" -eq 1 ] && [ "$target" -eq 1 ] && block "force-push/delete on a protected branch (--force, --force-with-lease, -f, +refspec, HEAD:main). Open a PR instead."
      ;;
    config)
      if printf '%s ' "${args[@]}" | grep -qi 'core\.hookspath' && ! printf ' %s ' "${args[@]}" | grep -qE ' (--get|--get-all|--get-regexp|get|-l|--list) '; then
        block "'git config core.hooksPath' re-points or disables the git-hook layer. Confirm with a human first."
      fi ;;
    checkout|restore)
      if printf ' %s' "${args[@]}" | grep -qE '[[:space:]](\./)?(\.claude/|\.claude([[:space:]]|$)|\.lefthook/|\.github/|lefthook\.yml|\.gitleaks\.toml|AGENTS\.md|CLAUDE\.md|docs/CONSTITUTION\.md)'; then
        block "'git checkout/restore' on a guard-layer file discards enforcement config (this is how settings.json gets silently wiped). Confirm with a human first."
      fi ;;
  esac
done <<< "$segments"

if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/"])(src|app|lib|test|\.claude|\.lefthook|\.git|node_modules)([[:space:]/"]|$)'; then
  block "recursive rm on a source directory. Confirm with a human first."
fi
exit 0
```

---

**`.claude/hooks/user-prompt-guard.py`** (FastAPI only):
```python
#!/usr/bin/env python3
# UserPromptSubmit — OWASP LLM01 injection guard + LLM02 credential-leak detection. Exit 2 = block.
import json, re, sys

try:
    prompt = json.load(sys.stdin).get('prompt', '') or ''
except Exception:
    sys.exit(0)
lower = prompt.lower()

injection = [
    'ignore previous instructions',
    'ignore all instructions',
    'forget your instructions',
    'new instructions:',
    'system prompt:',
    'your real instructions',
    'you are now a different ai',
    'you are no longer bound',
    'pretend you are not bound',
    'pretend you have no restrictions',
    'act as if you have no restrictions',
    'developer mode enabled',
]
# "disregard/override your ..." only when the object is the agent's own instructions —
# "override your config defaults" is an ordinary engineering request.
injection_re = re.compile(r'\b(disregard|override)\s+(all\s+)?(of\s+)?your\s+((previous|prior|original|current)\s+)?(instructions|rules|system\s+prompt|guidelines)\b')
hit = next((p for p in injection if p in lower), None)
if hit is None:
    m = injection_re.search(lower)
    hit = m.group(0) if m else None
if hit:
    sys.stderr.write(f'Blocked: prompt matches an injection pattern (OWASP LLM01): "{hit}"\n')
    sys.exit(2)

credentials = [
    (r'AKIA[0-9A-Z]{16}', 'AWS access key ID'),
    (r'ghp_[A-Za-z0-9]{36}', 'GitHub personal access token'),
    (r'github_pat_[A-Za-z0-9_]{82}', 'GitHub fine-grained PAT'),
    (r'sk-ant-[A-Za-z0-9\-_]{90,}', 'Anthropic API key'),
    (r'-----BEGIN [A-Z ]*PRIVATE KEY-----', 'PEM private key block'),
]
for pat, label in credentials:
    if re.search(pat, prompt):
        sys.stderr.write(f'Blocked: prompt may contain a real credential — {label} (OWASP LLM02). Do not paste secrets; use env vars.\n')
        sys.exit(2)
# DB/broker URL with embedded user:password — loopback hosts (local dev defaults) are exempt.
db_url = re.compile(r'(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp)://[^:/\s@]*:[^@\s/]+@(\[[^\]\s]*\]|[^/:\s?#,]+)', re.I)
loopback = {'localhost', '127.0.0.1', '[::1]'}
for m in db_url.finditer(prompt):
    if m.group(4).lower() not in loopback:
        sys.stderr.write('Blocked: prompt may contain a real credential — database/broker URL with embedded credentials (OWASP LLM02). Do not paste secrets; use env vars.\n')
        sys.exit(2)
sys.exit(0)
```

---

**`.claude/hooks/post-edit-typecheck.sh`** (typecheck command differs by stack — see delta table):

**For FastAPI — uses `python3` + `pyright`:**
```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on Python edits only. Feedback-only (never blocks).
# Errors reach Claude via hookSpecificOutput.additionalContext — plain stdout from a
# PostToolUse hook goes to the debug log only. Always exits 0.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
case "$file" in *.py|*.pyi) ;; *) exit 0 ;; esac
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
out=$(python -m pyright src/ 2>&1) && exit 0
errs=$(printf '%s\n' "$out" | grep -E ' - error' | head -20)
[ -n "$errs" ] || errs=$(printf '%s\n' "$out" | tail -20)
[ -n "$errs" ] || exit 0
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":("pyright reports type errors after this edit — fix them before moving on:\n"+sys.argv[1])[:9000]}}))' "$errs" 2>/dev/null
exit 0
```

---

**`.claude/hooks/post-edit-comment-check.sh`** (comment scanner — patterns from `.claude/comment-hygiene-patterns.txt`):

**For FastAPI — uses `python3` for JSON parsing:**
```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write) — flags change-narration comments and oversized comment blocks.
# Feedback-only (never blocks). Patterns come from .claude/comment-hygiene-patterns.txt.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
case "$file" in *.py) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

patterns=".claude/comment-hygiene-patterns.txt"
[ -f "$patterns" ] || exit 0

flagged=""
block_len=0
prev_lineno=0
while IFS= read -r cline; do
  lineno="${cline%%:*}"
  content="${cline#*:}"
  if [ "$prev_lineno" -ne 0 ] && [ "$lineno" -ne $((prev_lineno + 1)) ]; then
    [ "$block_len" -gt 5 ] && flagged="$flagged
  - oversized comment block ($block_len lines)"
    block_len=0
  fi
  stripped=$(printf '%s' "$content" | sed -E 's@^[[:space:]]*(#|""")[[:space:]]?@@')
  if [ -n "$stripped" ] && printf '%s' "$stripped" | grep -qEf "$patterns"; then
    flagged="$flagged
  - narration: $stripped"
  fi
  if printf '%s' "$content" | grep -qE '^[[:space:]]*#'; then
    block_len=$((block_len + 1))
  else
    [ "$block_len" -gt 5 ] && flagged="$flagged
  - oversized comment block ($block_len lines)"
    block_len=0
  fi
  prev_lineno="$lineno"
done < <(grep -nE '^[[:space:]]*(#|""")' "$file")
[ "$block_len" -gt 5 ] && flagged="$flagged
  - oversized comment block ($block_len lines, end of file)"

if [ -n "$flagged" ]; then
  msg="⚠ comment hygiene:$flagged"
  python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalContext':sys.argv[1]}}))" "$msg"
fi
exit 0
```

---

**`.claude/hooks/stop-checks.sh`** (test command differs by stack — see delta table). The early exit on a clean tree means a turn that changed nothing (or already committed its work — pre-commit/pre-push and CI gate that path) never pays for a test run; Claude Code also caps consecutive Stop-hook continuations at 8 by default (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`):

**For FastAPI — uses `python3` + `pytest`:**
```bash
#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | python3 -c "import json,sys
try: print('true' if json.loads(sys.stdin.read() or '{}').get('stop_hook_active') is True else 'false')
except Exception: print('false')" 2>/dev/null)
[ "$active" = "true" ] && exit 0
# Nothing uncommitted (no tracked diff vs HEAD, no new untracked files) → nothing new to test this turn.
if git rev-parse --verify -q HEAD >/dev/null 2>&1 && git diff --quiet HEAD -- . 2>/dev/null \
   && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
  exit 0
fi
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pytest --version >/dev/null 2>&1 || { echo "pytest unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(python -m pytest test/ -q 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
```

---

**`.claude/hooks/subagent-stop.sh`** (file extension and typecheck command differ by stack):

**For FastAPI — checks `.py`, uses `pyright`:**
```bash
#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted Python changes so it can't hand back broken code.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
meta=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    d=json.loads(sys.stdin.read() or '{}'); print(('true' if d.get('stop_hook_active') is True else 'false')+' '+str(d.get('agent_type') or ''))
except Exception: print('false ')" 2>/dev/null)
[ "${meta%% *}" = "true" ] && exit 0          # already re-running after a block — don't loop
case "${meta#* }" in Explore|Plan) exit 0 ;; esac   # read-only built-in agents never edit
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed=$( { git diff --name-only HEAD; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | grep -E '\.pyi?$' | head -1)
[ -n "$changed" ] || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
OUTPUT=$(python -m pyright src/ 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
```

---

## Step B2 — `lefthook.yml` (FastAPI)

**`lefthook.yml`** — FastAPI (Python tools; no pnpm):
```yaml
pre-commit:
  parallel: true
  commands:
    format-lint:
      glob: "*.py"
      # Exclude the enforcement layer: reformatting .claude/hooks/user-prompt-guard.py (and its
      # .harness-base snapshot copy) here would re-stage it with different bytes than Step E
      # hashed, making verify-harness.sh false-positive MODIFIED on the first commit.
      # .harness-base mirrors seeded files at their full original path (e.g.
      # .claude/.harness-base/.claude/hooks/user-prompt-guard.py); ** makes the "any depth"
      # intent explicit rather than relying on a single *'s cross-segment matching (verified
      # working under lefthook 2.1.10's default gobwas matcher, but not guaranteed by its docs).
      exclude:
        - .claude/hooks/*
        - .claude/.harness-base/**
      run: '[ -f .venv/bin/activate ] && . .venv/bin/activate; ruff format {staged_files} && ruff check --fix {staged_files}'
      stage_fixed: true
    typecheck:
      run: '[ -f .venv/bin/activate ] && . .venv/bin/activate; python -m pyright src/'
    secret-scan:
      # Skips only when gitleaks isn't installed locally (CI is the hard gate); a finding fails the commit.
      run: if command -v gitleaks >/dev/null 2>&1; then gitleaks protect --staged --redact --no-banner; fi
    readme-coupling:
      # Warn-only (never blocks): a folder with staged file changes should have its own
      # README.md staged too (per-folder documentation convention — see documentation-kit.md).
      # A root-level file (e.g. .env.example) is covered via folder "." — no special-casing needed.
      run: |
        tmp=$(mktemp)
        git diff --cached --name-only > "$tmp"
        missing=""
        while IFS= read -r f; do
          case "$f" in */README.md|README.md) continue ;; esac
          d=$(dirname "$f")
          rm_path="README.md"
          [ "$d" != "." ] && rm_path="$d/README.md"
          grep -qxF "$rm_path" "$tmp" || missing="$missing\n  - $d/"
        done < "$tmp"
        rm -f "$tmp"
        missing=$(printf '%b' "$missing" | sort -u)
        if [ -n "$missing" ]; then
          echo "⚠ folders changed without staging their README.md (commit still proceeds):"
          printf '%s\n' "$missing"
        fi
        exit 0
    comment-hygiene:
      # Warn-only (never blocks): flags change-narration comments and oversized comment
      # blocks. Patterns come from .claude/comment-hygiene-patterns.txt (see comments.md).
      run: |
        patterns=".claude/comment-hygiene-patterns.txt"
        [ -f "$patterns" ] || exit 0
        nl=$(printf '\nx'); nl=${nl%x}
        flagged=""
        # lefthook runs `run:` under sh — no `read -d ''`; stage the NUL-separated list as lines
        # in a temp file instead of word-splitting $(git diff), so paths with spaces survive.
        staged=$(mktemp)
        git diff --cached --name-only -z | tr '\0' '\n' > "$staged"
        while IFS= read -r f <&3; do
          case "$f" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py) ;; *) continue ;; esac
          [ -f "$f" ] || continue
          block_len=0
          prev_lineno=0
          candidates=$(mktemp)
          grep -nE '^[[:space:]]*(#|//|\*|"""|/\*\*?)' "$f" > "$candidates" || true
          while IFS= read -r cline; do
            lineno="${cline%%:*}"
            content="${cline#*:}"
            if [ "$prev_lineno" -ne 0 ] && [ "$lineno" -ne $((prev_lineno + 1)) ]; then
              [ "$block_len" -gt 5 ] && flagged="$flagged$nl  - $f: oversized comment block ($block_len lines)"
              block_len=0
            fi
            stripped=$(printf '%s' "$content" | sed -E 's@^[[:space:]]*(#|//|\*|"""|/\*\*?)[[:space:]]?@@')
            if [ -n "$stripped" ] && printf '%s' "$stripped" | grep -qEf "$patterns"; then
              flagged="$flagged$nl  - $f: $stripped"
            fi
            if printf '%s' "$content" | grep -qE '^[[:space:]]*(#|//)'; then
              block_len=$((block_len + 1))
            else
              [ "$block_len" -gt 5 ] && flagged="$flagged$nl  - $f: oversized comment block ($block_len lines)"
              block_len=0
            fi
            prev_lineno="$lineno"
          done < "$candidates"
          rm -f "$candidates"
          [ "$block_len" -gt 5 ] && flagged="$flagged$nl  - $f: oversized comment block ($block_len lines, end of file)"
        done 3< "$staged"
        rm -f "$staged"
        if [ -n "$flagged" ]; then
          echo "⚠ comment hygiene (commit still proceeds):"
          printf '%s\n' "$flagged"
        fi
        exit 0

commit-msg:
  commands:
    conventional:
      run: bash .lefthook/commit-msg.sh {1}
pre-push:
  commands:
    harness-integrity:
      run: bash .claude/verify-harness.sh
    verify:
      run: '[ -f .venv/bin/activate ] && . .venv/bin/activate; ruff check src/ && python -m pyright src/ && python -m pytest test/ -q'
```

> **Re-sync hooks after writing this file:** run `lefthook install` (inside the venv) now — Step 4's `pip install -r requirements-dev.txt` does not auto-run it the way the TS `prepare` script does, so `.git/hooks` is empty until this runs at least once.

---

## Step B3 — `.github/workflows/ci.yml` `quality` job (FastAPI)

**`.github/workflows/ci.yml`** — FastAPI (swap the `quality` job; the `changelog`, `readme-freshness`, and `comment-hygiene` jobs are identical):
```yaml
  quality:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { fetch-depth: 0 }
      - uses: actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0
        with:
          python-version: "3.14"
          cache: pip
          cache-dependency-path: requirements*.txt
      - name: Install deps
        run: |
          pip install -r requirements.txt
          [ -f requirements-dev.txt ] && pip install -r requirements-dev.txt || true
      - name: Harness integrity
        run: bash .claude/verify-harness.sh
      - run: ruff check src/ && ruff format --check src/
      - run: python -m pyright src/
      - run: python -m pytest test/ --cov=src --cov-report=xml -q   # writes coverage.xml
      - name: Changed-line coverage (>= 80%)
        run: pipx run diff-cover coverage.xml --compare-branch=origin/${{ github.base_ref || 'main' }} --fail-under=80
      - name: Secret scan (full history)
        uses: gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e # v3.0.0
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}   # required for org-owned repos (or run the gitleaks CLI instead)
```

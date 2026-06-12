<!-- ref: scaffold/shared/harness-kit.md
     loaded-by: scaffold/<stack>/source-files.md (all stacks) + migrate/general/implementation.md → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; scaffold app+config files already written (or migrate Phase 4 in progress). Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit

This file is the single source of truth for the Claude Code agent harness seeded into every scaffolded project. Read the **Per-stack delta table** first, then execute ALL numbered steps using the row matching the current stack.

---

## Per-stack delta table

| Stack | JSON-parsing runtime | Typecheck feedback cmd | Stop-checks test cmd | Verify-skill name(s) | Quality-gate line in CONSTITUTION §6 |
|-------|----------------------|------------------------|----------------------|----------------------|---------------------------------------|
| **fastapi** | `python3` | `python -m pyright src/ 2>&1 \| tail -5` | `python -m pytest test/ -q` | `api-verify` | `python -m pyright src/ && ruff check src/ && python -m pytest test/ -q` (the `/api-verify` skill) |
| **nestjs** | `node` | `pnpm exec tsc --noEmit --incremental 2>&1 \| tail -5` | `pnpm test --run` | `nest-verify` | `pnpm check` |
| **nextjs** | `node` | `pnpm exec tsc --noEmit --incremental 2>&1 \| tail -5` | `pnpm test --run` | `next-verify` + `next-migrate` | `pnpm check` |
| **vite-react** | `node` | `pnpm exec tsc --noEmit --incremental 2>&1 \| tail -5` | `pnpm test --run` | `vite-verify` | `pnpm check` |

**Additional per-stack notes:**
- `user-prompt-guard` filename: `user-prompt-guard.py` for **fastapi**; `user-prompt-guard.js` for all TS stacks.
- `user-prompt-guard` settings.json invocation: `python3 .claude/hooks/user-prompt-guard.py` (fastapi) vs `node .claude/hooks/user-prompt-guard.js` (TS stacks).
- `harness.json` `"stack"` value: use the lowercase stack name (`fastapi` / `nestjs` / `nextjs` / `vite-react`).
- `harness.json` verify-skill path: use the stack's verify-skill name(s) from the table above (next.js has two skills).
- CLAUDE.md hash in `harness.json`: all stacks use the conditional form `[ -f CLAUDE.md ] && sha256_claude=$(...)` — CLAUDE.md is created in a later optional step.

---

## Step A. Create `.claude/settings.json`

Create `.claude/settings.json` at the project root, plus the `.claude/hooks/` scripts it references (below). If `settings.json` already exists, merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, PostToolUseFailure, Stop, SubagentStop, SessionStart) and the `permissions.deny` list into the existing object rather than overwriting — preserve any hooks already present.

**`.claude/settings.json`** (substitute runtime from delta table for `user-prompt-guard`):

**For TS stacks (nestjs / nextjs / vite-react):**
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(**/.env)",
      "Read(**/.env.local)",
      "Read(**/.env.*.local)",
      "Read(**/.env.development)",
      "Read(**/.env.development.*)",
      "Read(**/.env.dev)",
      "Read(**/.env.production)",
      "Read(**/.env.production.*)",
      "Read(**/.env.staging)",
      "Read(**/.env.staging.*)",
      "Read(**/.env.uat)",
      "Read(**/.env.test)",
      "Read(./secrets/**)",
      "Read(./.secrets/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/protect-files.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/block-no-verify.sh" }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "node .claude/hooks/user-prompt-guard.js" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-edit-typecheck.sh" }]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-tool-failure.sh" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/stop-checks.sh" }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/subagent-stop.sh" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/session-context.sh" }]
      }
    ]
  },
  "skillListingBudgetFraction": 0.02
}
```

**For FastAPI:** identical shape; `UserPromptSubmit` runs `python3 .claude/hooks/user-prompt-guard.py` and the typecheck/test scripts use `pyright`/`pytest`:
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(**/.env)",
      "Read(**/.env.local)",
      "Read(**/.env.*.local)",
      "Read(**/.env.development)",
      "Read(**/.env.development.*)",
      "Read(**/.env.dev)",
      "Read(**/.env.production)",
      "Read(**/.env.production.*)",
      "Read(**/.env.staging)",
      "Read(**/.env.staging.*)",
      "Read(**/.env.uat)",
      "Read(**/.env.test)",
      "Read(./secrets/**)",
      "Read(./.secrets/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/protect-files.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/block-no-verify.sh" }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "python3 .claude/hooks/user-prompt-guard.py" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-edit-typecheck.sh" }]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-tool-failure.sh" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/stop-checks.sh" }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/subagent-stop.sh" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/session-context.sh" }]
      }
    ]
  },
  "skillListingBudgetFraction": 0.02
}
```

Hook logic lives in `.claude/hooks/` scripts (seeded below) so complex guards stay readable and testable rather than crammed into inline JSON. All are self-contained — no dependency on the templateCentral plugin, so the harness keeps enforcing even if the plugin is uninstalled.

- `protect-files.sh` (PreToolUse Edit|Write) — hard-blocks writes to `.env*` (except `.env.example`/`.env.default`), `secrets/` and `.secrets/` directories, `.github/workflows/`, cert/credential files; warns on governance files (`AGENTS.md`, `CLAUDE.md`, `Dockerfile`). Paired with `permissions.deny` above, which blocks *reading* secrets.
- `block-no-verify.sh` (PreToolUse Bash) — blocks `git commit --no-verify`, direct commits/force-push to protected branches (`main`/`uat`/`develop`), and `rm -rf` on source dirs.
- `user-prompt-guard` (UserPromptSubmit) — blocks prompt-injection phrases (OWASP LLM01) and inline credentials (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs). FastAPI: `.py` / TS stacks: `.js`.
- `post-edit-typecheck.sh` (PostToolUse) — incremental type feedback, filtered to source-file edits in-script. Feedback-only; exit 0 always. See delta table for typecheck command.
- `post-tool-failure.sh` (PostToolUseFailure) — surfaces tool error context for self-correction.
- `stop-checks.sh` (Stop) — runs the test suite; exit 2 forces a fix before the turn ends. See delta table for test command.
- `subagent-stop.sh` (SubagentStop) — type-gates a subagent's uncommitted changes so it can't hand back broken code.
- `session-context.sh` (SessionStart: startup/resume/clear/compact) — re-injects AGENTS.md routing context + universal invariants. This is the working post-compaction recovery path; PostCompact is observability-only and cannot inject context, so it is not used.
- `skillListingBudgetFraction` — caps skill-listing context overhead at 2 % of the budget.

---

## Step B. Create hook scripts

**`.claude/hooks/protect-files.sh`** (canonical — strongest variant, adopted from NestJS; blocks `secrets/*` and `.secrets/*` hard):

**For TS stacks (nestjs / nextjs / vite-react) — uses `node` for JSON parsing:**
```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write) — protect secrets, CI, cert, and governance files.
# Exit 2 = hard block; exit 1 = warn (human approval expected); exit 0 = allow.
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$file" ] && exit 0
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $base is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || root="."
rel="${file#"$root"/}"

if [[ "$rel" == .github/workflows/* ]]; then
  echo "BLOCKED: $rel is a CI/CD pipeline definition — requires human review." >&2
  exit 2
elif [[ "$rel" == secrets/* || "$rel" == .secrets/* ]]; then
  echo "BLOCKED: $rel is inside a secrets directory — must never be written by the agent." >&2
  exit 2
elif [[ "$rel" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $rel is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md) reason="binding invariants document — changes affect all agents and this project's behaviour" ;;
  .claude/settings.json) reason="harness config — editing it can silently disable every hook" ;;
  .claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  Dockerfile) reason="container image definition" ;;
esac
if [ -n "$reason" ]; then
  echo "PROTECTED FILE: $rel — $reason. Confirm human approval and note it in the PR." >&2
  exit 1
fi
exit 0
```

**For FastAPI — uses `python3` for JSON parsing:**
```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write) — protect secrets, CI, cert, and governance files.
# Exit 2 = hard block; exit 1 = warn (human approval expected); exit 0 = allow.
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
[ -z "$file" ] && exit 0
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $base is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || root="."
rel="${file#"$root"/}"

if [[ "$rel" == .github/workflows/* ]]; then
  echo "BLOCKED: $rel is a CI/CD pipeline definition — requires human review." >&2
  exit 2
elif [[ "$rel" == secrets/* || "$rel" == .secrets/* ]]; then
  echo "BLOCKED: $rel is inside a secrets directory — must never be written by the agent." >&2
  exit 2
elif [[ "$rel" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $rel is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md) reason="binding invariants document — changes affect all agents and this project's behaviour" ;;
  .claude/settings.json) reason="harness config — editing it can silently disable every hook" ;;
  .claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  Dockerfile) reason="container image definition" ;;
esac
if [ -n "$reason" ]; then
  echo "PROTECTED FILE: $rel — $reason. Confirm human approval and note it in the PR." >&2
  exit 1
fi
exit 0
```

---

**`.claude/hooks/block-no-verify.sh`** (runtime varies for JSON parsing only; logic is identical):

**For TS stacks — uses `node`:**
```bash
#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
input=$(cat)
cmd=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(((JSON.parse(b||'{}').tool_input)||{}).command||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$cmd" ] && exit 0

if echo "$cmd" | grep -qE 'git[[:space:]]+commit' && echo "$cmd" | grep -qE '\-\-no-verify|[[:space:]]-[a-z]*n'; then
  echo "BLOCKED: --no-verify (or -n) on git commit bypasses the pre-commit hooks. Fix the failure instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+commit'; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$branch" == "main" || "$branch" == "uat" || "$branch" == "develop" ]]; then
    echo "BLOCKED: direct commit to protected branch '$branch'. Create a feature branch first." >&2
    exit 2
  fi
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+push' && { { echo "$cmd" | grep -qE '\-\-force([[:space:]=]|$)|[[:space:]]-[a-z]*f' && echo "$cmd" | grep -qE '\bmain\b|\buat\b|\bdevelop\b'; } || echo "$cmd" | grep -qE '[[:space:]]\+(main|uat|develop)\b'; }; then
  echo "BLOCKED: force-push to a protected branch (--force/-f or +refspec). Open a PR instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/])(src|app|lib|test|\.claude|\.husky|\.git|node_modules)([[:space:]/]|$)'; then
  echo "BLOCKED: recursive rm on a source directory. Confirm with a human first." >&2
  exit 2
fi
exit 0
```

**For FastAPI — uses `python3`:**
```bash
#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)
[ -z "$cmd" ] && exit 0

if echo "$cmd" | grep -qE 'git[[:space:]]+commit' && echo "$cmd" | grep -qE '\-\-no-verify|[[:space:]]-[a-z]*n'; then
  echo "BLOCKED: --no-verify (or -n) on git commit bypasses the pre-commit hooks. Fix the failure instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+commit'; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$branch" == "main" || "$branch" == "uat" || "$branch" == "develop" ]]; then
    echo "BLOCKED: direct commit to protected branch '$branch'. Create a feature branch first." >&2
    exit 2
  fi
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+push' && { { echo "$cmd" | grep -qE '\-\-force([[:space:]=]|$)|[[:space:]]-[a-z]*f' && echo "$cmd" | grep -qE '\bmain\b|\buat\b|\bdevelop\b'; } || echo "$cmd" | grep -qE '[[:space:]]\+(main|uat|develop)\b'; }; then
  echo "BLOCKED: force-push to a protected branch (--force/-f or +refspec). Open a PR instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/])(src|app|lib|test|\.claude|\.husky|\.git|node_modules)([[:space:]/]|$)'; then
  echo "BLOCKED: recursive rm on a source directory. Confirm with a human first." >&2
  exit 2
fi
exit 0
```

---

**`.claude/hooks/user-prompt-guard.js`** (TS stacks only):
```javascript
#!/usr/bin/env node
// UserPromptSubmit — OWASP LLM01 injection guard + LLM02 credential-leak detection. Exit 2 = block.
const input = require('fs').readFileSync(0, 'utf8');
let prompt = '';
try { prompt = (JSON.parse(input || '{}').prompt) || ''; } catch { process.exit(0); }
const lower = prompt.toLowerCase();

const injection = [
  'ignore previous instructions',
  'ignore all instructions',
  'disregard your',
  'forget your instructions',
  'override your',
  'new instructions:',
  'system prompt:',
  'your real instructions',
  'you are now a different ai',
  'you are no longer bound',
  'pretend you are not bound',
  'pretend you have no restrictions',
  'act as if you have no restrictions',
  'developer mode enabled',
];
for (const p of injection) {
  if (lower.includes(p)) {
    process.stderr.write(`Blocked: prompt matches an injection pattern (OWASP LLM01): "${p}"\n`);
    process.exit(2);
  }
}

const credentials = [
  [/AKIA[0-9A-Z]{16}/, 'AWS access key ID'],
  [/ghp_[A-Za-z0-9]{36}/, 'GitHub personal access token'],
  [/github_pat_[A-Za-z0-9_]{82}/, 'GitHub fine-grained PAT'],
  [/sk-ant-[A-Za-z0-9\-_]{90,}/, 'Anthropic API key'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'PEM private key block'],
  [/mongodb(\+srv)?:\/\/[^:]+:[^@]+@/i, 'database URL with embedded credentials'],
];
for (const [re, label] of credentials) {
  if (re.test(prompt)) {
    process.stderr.write(`Blocked: prompt may contain a real credential — ${label} (OWASP LLM02). Do not paste secrets; use env vars.\n`);
    process.exit(2);
  }
}
process.exit(0);
```

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
    'disregard your',
    'forget your instructions',
    'override your',
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
for p in injection:
    if p in lower:
        sys.stderr.write(f'Blocked: prompt matches an injection pattern (OWASP LLM01): "{p}"\n')
        sys.exit(2)

credentials = [
    (r'AKIA[0-9A-Z]{16}', 'AWS access key ID'),
    (r'ghp_[A-Za-z0-9]{36}', 'GitHub personal access token'),
    (r'github_pat_[A-Za-z0-9_]{82}', 'GitHub fine-grained PAT'),
    (r'sk-ant-[A-Za-z0-9\-_]{90,}', 'Anthropic API key'),
    (r'-----BEGIN [A-Z ]*PRIVATE KEY-----', 'PEM private key block'),
    (r'mongodb(\+srv)?://[^:]+:[^@]+@', 'database URL with embedded credentials'),
]
for pat, label in credentials:
    if re.search(pat, prompt):
        sys.stderr.write(f'Blocked: prompt may contain a real credential — {label} (OWASP LLM02). Do not paste secrets; use env vars.\n')
        sys.exit(2)
sys.exit(0)
```

---

**`.claude/hooks/post-edit-typecheck.sh`** (typecheck command differs by stack — see delta table):

**For TS stacks — uses `node` + `pnpm exec tsc`:**
```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on TS edits only. Feedback-only (never blocks).
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
case "$file" in *.ts|*.tsx) ;; *) exit 0 ;; esac
pnpm exec tsc --version >/dev/null 2>&1 || exit 0
pnpm exec tsc --noEmit --incremental 2>&1 | tail -5
exit 0
```

**For FastAPI — uses `python3` + `pyright`:**
```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on Python edits only. Feedback-only (never blocks).
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
case "$file" in *.py) ;; *) exit 0 ;; esac
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
python -m pyright src/ 2>&1 | tail -5
exit 0
```

---

**`.claude/hooks/post-tool-failure.sh`** (runtime varies for JSON parsing only; logic is identical):

**For TS stacks — uses `node`:**
```bash
#!/usr/bin/env bash
# PostToolUseFailure — surface tool error context for self-correction. Always exit 0.
input=$(cat)
printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const d=JSON.parse(b||'{}');process.stderr.write('Tool failure: '+(d.tool_name||'unknown')+(d.error?(' — '+d.error):'')+'\n')}catch(e){}})" 2>/dev/null
exit 0
```

**For FastAPI — uses `python3`:**
```bash
#!/usr/bin/env bash
# PostToolUseFailure — surface tool error context for self-correction. Always exit 0.
input=$(cat)
printf '%s' "$input" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); sys.stderr.write('Tool failure: '+str(d.get('tool_name','unknown'))+((' — '+str(d.get('error'))) if d.get('error') else '')+'\n')
except Exception: pass" 2>/dev/null
exit 0
```

---

**`.claude/hooks/stop-checks.sh`** (test command differs by stack — see delta table):

**For TS stacks — uses `node` + `pnpm test`:**
```bash
#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(String(JSON.parse(b||'{}').stop_hook_active||false))}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] || [ "$active" = "True" ] && exit 0
command -v pnpm >/dev/null 2>&1 || { echo "pnpm unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(pnpm test --run 2>&1); EC=$?
echo "$OUTPUT" | tail -20 >&2
[ $EC -ne 0 ] && exit 2 || exit 0
```

**For FastAPI — uses `python3` + `pytest`:**
```bash
#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
input=$(cat)
active=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.loads(sys.stdin.read() or '{}').get('stop_hook_active', False))
except: print(False)" 2>/dev/null)
[ "$active" = "True" ] && exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pytest --version >/dev/null 2>&1 || { echo "pytest unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(python -m pytest test/ -q 2>&1); EC=$?
echo "$OUTPUT" | tail -20 >&2
[ $EC -ne 0 ] && exit 2 || exit 0
```

---

**`.claude/hooks/subagent-stop.sh`** (file extension and typecheck command differ by stack):

**For TS stacks — checks `.ts|.tsx`, uses `pnpm exec tsc`:**
```bash
#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted TS changes so it can't hand back broken code.
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
if git diff --name-only HEAD 2>/dev/null | grep -qE '\.(ts|tsx)$' || \
   git diff --cached --name-only 2>/dev/null | grep -qE '\.(ts|tsx)$'; then
  OUTPUT=$(pnpm exec tsc --noEmit 2>&1); EC=$?
  if [ $EC -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
fi
exit 0
```

**For FastAPI — checks `.py`, uses `pyright`:**
```bash
#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted Python changes so it can't hand back broken code.
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
if git diff --name-only HEAD 2>/dev/null | grep -qE '\.py$' || \
   git diff --cached --name-only 2>/dev/null | grep -qE '\.py$'; then
  OUTPUT=$(python -m pyright src/ 2>&1); EC=$?
  if [ $EC -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
fi
exit 0
```

---

**`.claude/hooks/session-context.sh`** (identical across all stacks — canonical):
```bash
#!/usr/bin/env bash
# SessionStart(startup|resume|clear|compact) — re-inject routing context + universal invariants.
# Plain stdout is added to Claude's context (per Claude Code hooks docs); this is what survives compaction.
echo "=== templateCentral routing context ==="
head -30 AGENTS.md 2>/dev/null

# If a CONSTITUTION.md exists, re-inject it (project binding invariants survive compaction)
if [ -f docs/CONSTITUTION.md ]; then
  echo ""
  echo "=== Project invariants (docs/CONSTITUTION.md) ==="
  cat docs/CONSTITUTION.md
fi

cat <<'EOF'

## Always-on invariants (survive compaction)
1. Secrets are never read or written by the agent — .env*, secrets/** and .secrets/** are guarded.
2. Run the quality gate (typecheck + tests) before declaring any task done.
3. Work on a feature branch — never commit directly to main/uat/develop.
4. Protected files — AGENTS.md, CLAUDE.md, Dockerfile, .claude/settings.json, .claude/hooks/*, docs/CONSTITUTION.md — require human approval.
5. Respect the architecture/dependency boundaries documented in AGENTS.md and docs/CONSTITUTION.md.
EOF
```

Make all hook scripts executable:
```bash
chmod +x .claude/hooks/*.sh
```

---

## Step C. Create `FUTURE.md`

Create `FUTURE.md` at the project root:

**`FUTURE.md`**:
```markdown
# Future Directions

Design seams built into this project for AI collaboration patterns that are not yet activated. These are integration points, not features — nothing here runs unless you build it.

## Meta-Harness

CI that validates this project's own harness: a job that scaffolds the project and asserts the output passes tests and lint. Most near-term post-harness direction.

**Seam:** `<!-- [[post-harness:meta]] -->` in `AGENTS.md` — reserved for meta-harness CI configuration.

## Trace-Driven Evolution

Capture agent decision traces across sessions, aggregate patterns, and use them to improve conventions over time. Off by default.

**Seam:** The disabled trace hook placeholder in `.claude/settings.json`.

## Environment Engineering

A fully specified, reproducible environment ensuring every agent session starts from the same known state. Think devcontainers or Nix flakes with agent-specific overlays.

**Seam:** `devcontainer.json` if present.

---

*Seams from [templateCentral v4.0](https://github.com/cljiahao/templatecentral). None activated.*
```

---

## Step D. Seed `docs/CONSTITUTION.md`

Create `docs/CONSTITUTION.md` as the binding invariants document for this project.
It takes precedence over `AGENTS.md` and all skill guidance when there is a conflict.
Fill in the `[...]` placeholders with the actual project values.
Use the **quality-gate line** from the per-stack delta table in §6 Behavioural rules.

**`docs/CONSTITUTION.md`**:
```markdown
# CONSTITUTION.md

## 1. Purpose

This document defines the non-negotiable invariants for **[Project Name]**.
It applies to all contributors — human and AI agent alike. When `AGENTS.md`,
templateCentral skills, or any other guidance conflicts with this document,
**this document wins**. No PR may be merged that violates these rules without
an explicit `## Human Approval Override` section in the PR description.

## 2. Architecture Invariants

[Define the load-bearing architectural rules: layering, module boundaries,
factory/composition-root patterns, forbidden cross-imports, etc.]

## 3. Security Invariants

- Secrets NEVER appear in code, git, logs, or build output — use environment
  variables loaded from a secrets manager.
- All API routes authenticate before executing business logic.
- All mutations write to an audit log.

## 4. Testing Invariants

- New services must have integration tests (success, error, at least one edge case).
- New API routes must have route tests covering 401, 200, and at least one error path.
- CI must stay green — no PR may be merged with failing tests.

## 5. Git & PR Invariants

- Branch from `main`. Protected branches (`main`, `uat`, `develop`) — no direct commits.
- Every PR to `uat` and `main` requires the PR template fully filled.

## 6. Agent Governance Rules

### Protected files — human approval required

The following files require explicit human approval noted in the PR under
`## Protected File Changes`. Agents MUST NOT modify them without approval.

- `AGENTS.md` / `CLAUDE.md` — agent instruction files
- `docs/CONSTITUTION.md` — this document
- `.claude/settings.json` — harness wiring
- `.claude/hooks/*` — enforcement hooks
- `Dockerfile`
[Add project-specific protected files here]

### Behavioural rules

- Run the quality gate (see delta table for stack-specific command) before declaring any task done.
- Never use `--no-verify` on commits — this bypasses pre-commit hooks.
- Work on a feature branch — never commit directly to `main`, `uat`, or `develop`.
```

---

## Step E. Create `.claude/harness.json`

**Prerequisites:** Run this step only after the verify skills (and `next-migrate` for nextjs) have been created in `.claude/skills/` — these are seeded by the stack file's step 6c, which runs between the kit's Steps D and E. Do not run Step E before step 6c.

Compute SHA-256 hashes and write `.claude/harness.json`. CLAUDE.md is created in a later optional step — hash it conditionally.

```bash
sha256_agents=$(shasum -a 256 AGENTS.md | cut -d' ' -f1)
# Every enforcement hook script is a high-value tamper target — hash each for drift detection.
# Add a seeded_files entry (origin_hash + path) for EACH line printed below, alongside the core files:
for h in .claude/hooks/*; do shasum -a 256 "$h"; done
# CLAUDE.md is optional (Step G) — hash it only if it already exists
[ -f CLAUDE.md ] && sha256_claude=$(shasum -a 256 CLAUDE.md | cut -d' ' -f1)
sha256_settings=$(shasum -a 256 .claude/settings.json | cut -d' ' -f1)
# Hash the verify skill (created in the stack file's step 6c before reaching this step):
sha256_verify=$(shasum -a 256 .claude/skills/<stack>-verify/SKILL.md | cut -d' ' -f1)
# For nextjs only — also hash the migrate skill (also created in step 6c):
sha256_migrate=$(shasum -a 256 .claude/skills/next-migrate/SKILL.md | cut -d' ' -f1)
```

**`.claude/harness.json`** (substitute stack name, verify-skill path, and computed hashes):
```json
{
  "templatecentral_version": "5.0.0",
  "stack": "<stack>",
  "seeded_at": "<ISO-date>",
  "seeded_files": {
    "AGENTS.md": { "origin_hash": "<sha256_agents>", "path": "AGENTS.md" },
    "CLAUDE.md": { "origin_hash": "<sha256_claude>", "path": "CLAUDE.md" },
    ".claude/settings.json": { "origin_hash": "<sha256_settings>", "path": ".claude/settings.json" },
    ".claude/skills/<stack>-verify/SKILL.md": { "origin_hash": "<sha256_verify>", "path": ".claude/skills/<stack>-verify/SKILL.md" },
    ".claude/hooks/protect-files.sh": { "origin_hash": "<sha256_hook_1>", "path": ".claude/hooks/protect-files.sh" },
    ".claude/hooks/block-no-verify.sh": { "origin_hash": "<sha256_hook_2>", "path": ".claude/hooks/block-no-verify.sh" },
    ".claude/hooks/user-prompt-guard.<ext>": { "origin_hash": "<sha256_hook_3>", "path": ".claude/hooks/user-prompt-guard.<ext>" },
    ".claude/hooks/post-edit-typecheck.sh": { "origin_hash": "<sha256_hook_4>", "path": ".claude/hooks/post-edit-typecheck.sh" },
    ".claude/hooks/post-tool-failure.sh": { "origin_hash": "<sha256_hook_5>", "path": ".claude/hooks/post-tool-failure.sh" },
    ".claude/hooks/stop-checks.sh": { "origin_hash": "<sha256_hook_6>", "path": ".claude/hooks/stop-checks.sh" },
    ".claude/hooks/subagent-stop.sh": { "origin_hash": "<sha256_hook_7>", "path": ".claude/hooks/subagent-stop.sh" },
    ".claude/hooks/session-context.sh": { "origin_hash": "<sha256_hook_8>", "path": ".claude/hooks/session-context.sh" }
  }
}
```

> `user-prompt-guard.<ext>` is `.js` for TS stacks (nestjs, nextjs, vite-react) and `.py` for FastAPI.
> Omit the `CLAUDE.md` entry if `CLAUDE.md` does not exist yet — it is created in Step G (optional). If you create it there, append its entry to `seeded_files` with the hash at that point.
> For **nextjs**, also add a `".claude/skills/next-migrate/SKILL.md"` entry.

---

## Step F. Create `.agents` symlink

Create the cross-vendor symlink so the project works with any agent framework that resolves from `.agents/`:

```bash
ln -s .claude .agents
```

This makes `AGENTS.md`, `settings.json`, `rules/`, `skills/`, and `hooks/` discoverable by Claude Code (`.claude/`) and any other tool that looks in `.agents/` — one source of truth, zero duplication.

---

## Step G. Post-scaffold agent workflow

**AGENTS.md tail — append only if not already present:** Some stack files (nextjs, fastapi) embed the `## AI Harness` and `## Skills Security` sections directly in their AGENTS.md template. Before appending the shared tail fragment below, check whether `## AI Harness` already appears in the AGENTS.md just written. If it does, skip the append — the content is already there. If it does not (e.g., nestjs, vite-react, or migrate paths), append it now.

After the stack-specific AGENTS.md is written (appending the shared tail fragment if not already present), run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — verify the scaffold compiles clean
2. the test utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/test/SKILL.md"` — verify all scaffold tests pass
3. the review utility (update operation) — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — freshen any deps that have newer compatible versions
4. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip these steps if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

---

## Step H. Install Claude Code plugins

**Claude Code users only.** Install these plugins in the scaffolded project directory. These are **on by default** — skip only if the user explicitly opts out.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add obra/superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

---

## Shared AGENTS.md tail fragment

**Append this below the stack-specific AGENTS.md template** (after the stack's Rules section, before the closing line if any):

```markdown
## AI Harness
PreToolUse: blocks secrets and CI pipeline files only (exit 2): `.env*` (except `.env.example`), `.github/workflows/`, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`; a second Bash guard blocks `--no-verify` and force-pushes to protected branches. Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/clear/compact): re-injects AGENTS.md routing context + universal invariants so they survive compaction (PostCompact is observability-only and cannot inject).
UserPromptSubmit: pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.
PostToolUse: incremental type-check (see delta table for stack command) after every Edit/Write. Feedback-only.
Stop hook: runs full test suite; exit 2 feeds failures to Claude via stderr; exit 0 on pass.
Project skills: `.claude/skills/` | Manifest: `.claude/harness.json`
Context load order (context only — not enforcement, broad → specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → this file → `.claude/rules/*.md` (lazy per-directory). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security
- Review `SKILL.md` content before installing any third-party skill — treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (e.g. `Bash(git *)` not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.
```

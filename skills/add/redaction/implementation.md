<!-- ref: add/redaction/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack identified; project already has the templateCentral harness seeded (scaffold or migrate). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

## Step 0 — Verify context

Confirm `.claude/settings.json` and `.claude/hooks/user-prompt-guard.cjs` (TS) or `.py` (FastAPI)
exist — this extends the harness. If not, run `templatecentral:migrate` (Project-migration path) first, then re-check.

## Step 1 — Collect real values from the user

Ask the user for their project's real infrastructure values:

1. Real internal CIDR range(s) they want masked, e.g. `172.18.161.0/24`. IPv4 only.
2. Real internal domain suffix(es) they want masked, e.g. `corp.internal`.

At least one CIDR or domain suffix is required; with neither (no deployed infra yet), stop and tell the
user to come back later.

Ask for the **narrowest** ranges in use (`/16`s or `/24`s), not a supernet: each real range maps onto a
same-sized synthetic block disjoint from all real ranges, so one that swallows a whole synthetic space
(a full `10.0.0.0/8`) cannot be masked and the hook refuses.

## Step 2 — Write `.claude/redaction-config.json`

Substitute the user's real values for the example below (JSON, not YAML — both hook runtimes parse it
with zero added dependencies):

```json
{
  "cidrs": ["172.18.161.0/24"],
  "domains": ["corp.internal"]
}
```

The mapping file (`.claude/.redaction-map.json`, created on first mask) is gitignored (Step 7), so
synthetic values are stable within one checkout, not across a team.

## Step 3 — Seed the `PostToolUse` hook

The hook code is runtime-specific — load **only** the file for this stack and follow its **Part A**
(it also carries the Step 6 companion snippet as **Part B**, so keep it in context):

| Stack | Hook runtime | Load |
|---|---|---|
| nestjs / nextjs / vite-react | Node (`.claude/hooks/redact-sensitive-output.cjs`) | `cat "<skill-dir>/redaction/hook-node.md"` |
| fastapi | Python (`.claude/hooks/redact_sensitive_output.py`) | `cat "<skill-dir>/redaction/hook-python.md"` |

## Step 4 — Wire the hook into `.claude/settings.json`

Merge this entry into the existing `hooks.PostToolUse` array (do not overwrite other entries — same
merge convention as `harness-kit-enforcement.md` Step A):

**TS stacks:**
```json
{
  "matcher": "Bash|Read|Grep|Glob",
  "hooks": [{ "type": "command", "command": "node", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/redact-sensitive-output.cjs"], "timeout": 10 }]
}
```

**FastAPI:**
```json
{
  "matcher": "Bash|Read|Grep|Glob",
  "hooks": [{ "type": "command", "command": "python3", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/redact_sensitive_output.py"], "timeout": 10 }]
}
```

Also merge these two entries into `permissions.deny` (do not remove existing entries):

```json
"Read(.claude/redaction-config.json)",
"Read(.claude/.redaction-map.json)"
```

Load-bearing: both files hold the real values in plaintext, so an agent that reads them defeats the masking.

The deny covers `Read` and recognised file-reading Bash commands (`cat`, `head`, `tail`, …), not an
arbitrary subprocess (`python -c`, `node -e`) — a deterrent, not an OS-level guarantee.

## Step 5 — Extend `protect-files.sh`

Give the two redaction files their own case arm in `.claude/hooks/protect-files.sh` (human approval
required before write) — add it alongside the existing `.claude/hooks/*` and `.claude/harness.json`
arms, not folded into them, so the approval prompt states the real reason:

```bash
  .claude/redaction-config.json|*/.claude/redaction-config.json|.claude/.redaction-map.json|*/.claude/.redaction-map.json) reason="redaction policy config — editing it can weaken or disable masking of real infra data" ;;
```

## Step 6 — Add the companion warning to `user-prompt-guard`

Apply **Part B** of the runtime file loaded in Step 3 — it names the exact insertion point in
`.claude/hooks/user-prompt-guard.cjs` (TS stacks) or `.claude/hooks/user-prompt-guard.py` (FastAPI).

## Step 7 — Gitignore the map file

Add this line to `.gitignore` if not already present:

```
.claude/.redaction-map.json
```

`.claude/redaction-config.json` is not gitignored — commit it so the team shares the policy; only the
mapping stays local.

## Step 8 — Re-bless the harness-integrity baseline

`verify-harness.sh` (CI gate and pre-push hook) hashes the edited `.claude/settings.json` and
`.claude/hooks/*` against `.claude/harness.json`, so every push fails until the baseline is refreshed.
Tell the user (do not run it yourself — re-blessing is a human act, gated by `protect-files.sh`):

> Run `bash .claude/regen-harness.sh` yourself, review the diff, and commit it. While doing so, add
> `.claude/hooks/redact-sensitive-output.cjs` (or `.claude/hooks/redact_sensitive_output.py`) to
> `harness.json`'s `seeded_files` so the redaction hook is itself drift-protected from here on.

**Re-sync caveat:** `templatecentral:migrate`'s Phase 5d treats `.claude/hooks/*` as the enforcement
layer and overwrites it with canonical content, which silently removes the `user-prompt-guard` companion
patch from Step 6 (`.claude/settings.json` is merged structurally, so the `PostToolUse` entry survives).
After any harness re-sync, re-apply Step 6 and re-run Step 9.

## Step 9 — Confirm

```bash
node -e "require('./.claude/hooks/redact-sensitive-output.cjs')" 2>&1 | head -5   # TS stacks: loads without error
python3 -c "import sys; sys.path.insert(0,'.claude/hooks'); import redact_sensitive_output"  # FastAPI: loads without error
grep -q "PostToolUse" .claude/settings.json
grep -q "redaction-config.json" .claude/settings.json
# structured-output contract: masks the string leaves, keeps the rest of the shape
echo '{"tool_response":{"stdout":"host at <a real IP from the configured range>","stderr":"","interrupted":false,"isImage":false}}' \
  | node .claude/hooks/redact-sensitive-output.cjs   # FastAPI: python3 .claude/hooks/redact_sensitive_output.py
```

The last check must print an `updatedToolOutput` **object** (`{"stdout":...,"stderr":"","interrupted":false,"isImage":false}`)
with the real IP replaced — Claude Code silently drops a flat string for built-in tools.

Capability is complete once all five checks pass.

## Scope and limitations

- **Tool coverage.** The `Bash|Read|Grep|Glob` matcher is the v1 scope boundary, deliberately chosen
  because those four are where infra data surfaces in practice. `WebFetch`, MCP tool results, and
  subagent/`Task` output are not masked — treat them as unprotected surfaces, not as an oversight.
- **Range sizing.** A declared real range that covers an entire synthetic space has no disjoint block to
  map onto; the hook emits a named warning (as a user-facing `systemMessage`) and passes the output through unmasked rather than
  emitting a "mask" identical to the input. Declare narrower ranges (see Step 1).
- **Fail-open by design.** Malformed config, invalid CIDR entries, an unsatisfiable address plan, or any
  unexpected error during masking all produce a `systemMessage` warning (plain stderr on exit 0 would
  reach only the debug log) and exit 0. The hook never blocks a tool
  call; a broken redaction config degrades to no masking, visibly, not to a stalled session.

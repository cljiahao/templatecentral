# OpenCode harness adapter

Ports templateCentral's Claude Code in-agent guards (`.claude/hooks/`) to an OpenCode plugin, so an
OpenCode / OpenChamber user gets the same live protection. The git-hook + CI half of the harness
(lefthook, gitleaks, the CI workflow) is already tool-agnostic and needs no adapter — this covers
only the in-agent guards.

## Guard parity

| Claude Code hook | OpenCode hook | Behavior |
|---|---|---|
| `block-no-verify.sh` (PreToolUse Bash) | `tool.execute.before` (bash) | Hard-block (throws): `git commit --no-verify`/`-n`, commit on `main`/`uat`/`develop`, force-push to a protected branch, `git checkout/restore` of a guard file, `rm -rf` of a source dir. |
| `protect-files.sh` (PreToolUse Edit\|Write) | `tool.execute.before` (edit/write) | Hard-block (throws): `.env*` (except `.env.example`/`.env.default`), `secrets/`, cert/credential files, and governance files (`AGENTS.md`, `CLAUDE.md`, `docs/CONSTITUTION.md`, `.claude/**`, `Dockerfile`, `lefthook.yml`, `.gitleaks.toml`). |
| `post-edit-typecheck.sh` (PostToolUse) | `tool.execute.after` (edit/write) | Feedback only (never blocks): runs `tsc --noEmit` (TS) or `pyright` (Python) and prints errors. |

**Not ported** (no clean OpenCode equivalent yet): the Stop test-gate (`stop-checks.sh`), SubagentStop
type-gate, and SessionStart context re-injection. OpenCode has no blocking end-of-turn plugin hook;
the test-gate stays enforced at commit/CI time via lefthook + the CI workflow. If OpenCode adds a
blocking session-idle/turn-end hook, wire the test command in the `event` handler.

> **Difference from Claude Code:** the CC `protect-files` hook raises a soft *"ask the human"* prompt
> for governance files. OpenCode plugins can't raise that prompt mid-tool, so this adapter
> **hard-blocks** governance-file edits with a "confirm and re-run intentionally" message. Adjust to
> your team's preference if you want a softer gate (e.g. an allowlist env var).

## Install

Add to `opencode.json` (project `./opencode.json` or global `~/.config/opencode/opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["/abs/path/to/templateCentral/adapters/opencode/templatecentral.plugin.js"]
}
```

Or drop the file into `.opencode/plugin/` in your project (OpenCode auto-discovers `*.js`/`*.ts`
there). OpenCode loads config once at startup — **restart OpenCode after installing.**

## Validation

The pure guard logic (which commands/files are blocked vs allowed) is unit-tested and ships green:

```bash
node --check adapters/opencode/templatecentral.plugin.js   # syntax
# 22-case logic test — see the repo's validation run; re-run with your own cases as needed.
```

**Live smoke test (needs a real OpenCode run with your credentials).** OpenCode's internal tool-arg
key names can shift between versions, so confirm the hooks actually fire end-to-end:

1. Install the plugin (above) and restart OpenCode in a scratch git repo.
2. Ask the agent: *"run `git commit --no-verify -m test`"* → expect it **blocked** with
   `[templatecentral] BLOCKED: --no-verify …`.
3. Ask the agent: *"create a file named `.env` with `API_KEY=x`"* → expect it **blocked**.
4. Ask the agent to *"create `.env.example`"* and *"edit `src/foo.ts`"* → expect both **allowed**.
5. Edit a TS file with a type error → expect a `[templatecentral] typecheck feedback:` note (not a block).

If a guard doesn't fire, check the arg key your OpenCode version uses for the bash command / file
path (the plugin reads `args.command`/`args.cmd` and `args.filePath`/`args.path`/`args.file_path`
defensively) and adjust `tool.execute.before` accordingly.

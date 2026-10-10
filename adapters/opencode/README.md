# OpenCode harness adapter

Ports templateCentral's Claude Code in-agent guards (`.claude/hooks/`) to an OpenCode plugin, so an
OpenCode / OpenChamber user gets the same live protection. The git-hook + CI half of the harness
(lefthook, gitleaks, the CI workflow) is already tool-agnostic and needs no adapter — this covers
only the in-agent guards.

## Guard parity

| Claude Code hook | OpenCode hook | Behavior |
|---|---|---|
| `block-no-verify.sh` (PreToolUse Bash) | `tool.execute.before` (bash) | Hard-block (throws), evaluated per chained command (`&&`, `;`, `\|`, `bash -c "…"`, heredoc bodies ignored): `--no-verify` on commit/push/merge/rebase/etc., `-n` as a `git commit` flag only, `LEFTHOOK=0`/`LEFTHOOK_EXCLUDE`, `core.hooksPath` overrides (`-c`, `git config`, `GIT_CONFIG_*`), `--no-verify` aliases, commit on `main`/`uat`/`develop`, force-push/delete of a protected branch (`--force`, `--force-with-lease`, `-f`, `+ref`, `:ref`, `HEAD:main`), `git checkout/restore` of a guard file, `rm -rf` of a source dir. |
| `protect-files.sh` (PreToolUse Edit\|Write) | `tool.execute.before` (edit/write) | Hard-block (throws), case-insensitive on a normalised project-relative path: `.env*` (except `.env.example`/`.env.default`), `secrets/`/`.secrets/`, CI/CD pipeline files, cert/credential files, and governance files (`AGENTS.md`, `CLAUDE.md`, `docs/CONSTITUTION.md`, `.claude/settings*.json`, `.claude/hooks/`, `.claude/agents/`, `.mcp.json`, harness baseline/verifier, `Dockerfile`, `lefthook.yml`, `.lefthook/`, `.gitleaks.toml`). Unlike the CC hook, symlinked parents are not resolved. |
| `post-edit-typecheck.sh` (PostToolUse) | `tool.execute.after` (edit/write) | Feedback only (never blocks): after a `.ts/.tsx/.mts/.cts` or `.py/.pyi` edit, runs `tsc --noEmit --incremental` or `pyright` and appends errors to the tool result. |
| `user-prompt-guard.<ext>` (UserPromptSubmit) | **Not ported** | **Claude-Code-only — no OpenCode equivalent shipped.** The prompt-injection guard (OWASP LLM01) and inline-credential guard (OWASP LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs) that Claude Code runs on every incoming prompt is **not** available in this adapter. OpenCode users get none of that prompt-level protection today — don't assume parity here. |

**Not ported** (no clean OpenCode equivalent yet): the `user-prompt-guard` injection/credential guard
(see table above), the Stop test-gate (`stop-checks.sh`), SubagentStop type-gate, and SessionStart
context re-injection. OpenCode has no blocking `UserPromptSubmit`-equivalent or end-of-turn plugin
hook; the test-gate stays enforced at commit/CI time via lefthook + the CI workflow. If OpenCode adds
a blocking prompt-submit or session-idle/turn-end hook, port `user-prompt-guard` and wire the test
command in the `event` handler.

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

Or drop the file into `.opencode/plugins/` in your project (or `~/.config/opencode/plugins/` globally)
— OpenCode auto-loads `*.js`/`*.ts` from those directories ([docs](https://opencode.ai/docs/plugins/)). OpenCode loads config once at startup — **restart OpenCode after installing.**

## Validation

The guard logic is unit-tested through the plugin's hooks:

```bash
node adapters/opencode/hooks.test.mjs   # block/allow matrix + typecheck feedback, through the default export
```

**Live smoke test (needs a real OpenCode run with your credentials).** OpenCode's internal tool-arg
key names can shift between versions, so confirm the hooks actually fire end-to-end:

1. Install the plugin (above) and restart OpenCode in a scratch git repo.
2. Ask the agent: *"run `git commit --no-verify -m test`"* → expect it **blocked** with
   `[templatecentral] BLOCKED: --no-verify …`.
3. Ask the agent: *"create a file named `.env` with `API_KEY=x`"* → expect it **blocked**.
4. Ask the agent to *"create `.env.example`"* and *"edit `src/foo.ts`"* → expect both **allowed**.
5. Edit a TS file with a type error → expect a `[templatecentral] typecheck reports errors` note in the tool result (not a block).

If a guard doesn't fire, check the arg key your OpenCode version uses for the bash command / file
path (the plugin reads `args.command`/`args.cmd` and `args.filePath`/`args.path`/`args.file_path`
defensively) and adjust `tool.execute.before` accordingly.

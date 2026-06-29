# Using templateCentral with other agent tools

**Claude Code is templateCentral's primary, fully-featured target** — marketplace install plus the
complete in-agent hook harness. This document covers using the skill library from other agent tools
(OpenCode / OpenChamber, OpenAI Codex, Google Antigravity, and any tool implementing the open
Agent-Skills standard). Cross-tool support is strictly additive and never regresses the Claude Code
experience.

## What's portable, and why

templateCentral is built on two cross-vendor open standards, so most of it travels unchanged:

| Layer | Portable? | Notes |
|---|---|---|
| **Skills** (`skills/`) | ✅ | [Agent Skills](https://agentskills.io) open standard (`SKILL.md`). The `<skill-dir>` reference form resolves in every compliant tool — each surfaces the skill's base directory at invocation (Claude Code & OpenCode print `Base directory for this skill:`, Codex injects the skill's `(file: …)` path, Antigravity resolves relative paths from the skill root). |
| **`AGENTS.md`** | ✅ | A Linux Foundation / Agentic AI Foundation standard. Read natively by Codex and Antigravity; Claude Code reads it via the `CLAUDE.md = @AGENTS.md` import. |
| **Harness — git/CI half** | ✅ | lefthook git-hooks + gitleaks + the seeded CI workflow fire at commit/CI time for any tool or human. |
| **Harness — in-agent half** | per-tool | `.claude/hooks/` + `settings.json` are Claude Code-specific. An OpenCode adapter lives at [`adapters/opencode/`](../adapters/opencode/) (Phase 3). |

**The one snag: skill naming.** templateCentral's registered skills are named with the
`templatecentral:` namespace (e.g. `name: templatecentral:scaffold`) — a Claude Code plugin
convention. The Agent-Skills standard requires `name` to be lowercase-hyphen and to match the skill's
directory name. Run the generator below to produce a tool-agnostic copy with the namespace stripped.

```bash
bash scripts/build-agents-dist.sh
# -> dist/agents-skills/   (skill names == folder names: scaffold, add, migrate, standards, …)
```

`dist/` is a gitignored build artifact. Re-run the script after pulling updates.

## Per-tool setup

### OpenCode / OpenChamber

OpenChamber wraps OpenCode, so the same runtime applies. Register the generated skills via
`skills.paths` in `opencode.json` (project `./opencode.json` or global
`~/.config/opencode/opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": { "paths": ["/abs/path/to/templateCentral/dist/agents-skills"] }
}
```

OpenCode scans the path recursively for `**/SKILL.md`. Alternatively, copy `dist/agents-skills/*`
into `~/.config/opencode/skills/` (global) or a project `.opencode/skills/`. OpenCode also
auto-loads `~/.claude/skills/` and `~/.agents/skills/` if you prefer to stage them there. Restart
OpenCode after changing config — it loads config once at start.

### OpenAI Codex

Codex auto-discovers skills under `.agents/skills/` (walking from the cwd up to the repo root),
`~/.agents/skills/` (user), and `/etc/codex/skills/` (admin). Copy or symlink the generated skills
into one of those:

```bash
mkdir -p ~/.agents/skills
cp -R dist/agents-skills/* ~/.agents/skills/
```

Codex reads `AGENTS.md` natively (global `~/.codex/` → repo root → nested, closest-wins). Invoke a
skill explicitly with `/skills` or `$<skill-name>`, or let Codex auto-select by description.

### Google Antigravity

Antigravity discovers skills under a project's `.agents/skills/` and global
`~/.gemini/config/skills/`. Copy the generated skills there:

```bash
mkdir -p .agents/skills
cp -R dist/agents-skills/* .agents/skills/
```

Antigravity reads `AGENTS.md` (applied after `GEMINI.md`). Skills auto-activate by description.

### Any other Agent-Skills tool

Cursor, Gemini CLI, GitHub Copilot, Zed, Amp, Windsurf, and others implement the same standard.
Point the tool at `dist/agents-skills/` (or copy it into the tool's skill directory) and ensure
`AGENTS.md` is present at the project root.

## What you get without Claude Code

A non-Claude-Code user gets the full scaffold logic, the `AGENTS.md` routing/conventions, and the
git-hook + CI enforcement — roughly 80% of the value. The remaining 20% (the in-agent live guards:
typecheck-on-edit, the Stop test-gate, secret/prompt-injection guards, session recovery) is
Claude Code-specific; an OpenCode port is in [`adapters/opencode/`](../adapters/opencode/).

## Publishing to a registry (maintainer step)

To make the skills installable beyond a git clone, publish `dist/agents-skills/` to an
Agent-Skills registry (e.g. an `agents.toml`/skills-supply index or an open marketplace). This is an
outward-facing, credentialed action — perform it deliberately, not as part of routine CI.

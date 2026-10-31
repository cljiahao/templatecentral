<!-- ref: add/redaction/hook-node.md
     loaded-by: add/redaction/implementation.md → add/SKILL.md
     prereq: Stack is NestJS, Next.js, or Vite + React (Node hook runtime); add (redaction) Steps 0–2 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Redaction hooks — Node runtime (TS stacks)

Contents: **Part A** — the `PostToolUse` masking hook (implementation.md Step 3). **Part B** — the `user-prompt-guard` companion warning (implementation.md Step 6). Apply Part A now, then continue implementation.md at Step 4; apply Part B when it reaches Step 6.

### Part A — `PostToolUse` masking hook

Run `TC_PART=leaf TC_LEAF=add/redaction/hook-node bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/redaction/hook-node/template/` (listed in `<skill-dir>/redaction/hook-node/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**For TS stacks (nestjs / nextjs / vite-react)** — write `.claude/hooks/redact-sensitive-output.cjs`:

Copied verbatim from `<skill-dir>/redaction/hook-node/template/.claude/hooks/redact-sensitive-output.cjs` by the copy step; do not re-type it.

### Part B — `user-prompt-guard` companion warning

**For TS stacks** — in `.claude/hooks/user-prompt-guard.cjs`, insert immediately before the final
`process.exit(0);` (leave the injection and credential hard-block paths above it untouched):

```javascript
// Redaction companion (OWASP LLM02 infra-topology variant) — only active if add (redaction) has been applied.
// Warns, never blocks: the human is the one party allowed to reference real infra values.
// The warning goes out as `systemMessage`, a human-facing surface. It must NOT go to plain
// stdout or additionalContext: on UserPromptSubmit those can be injected into the model's
// context, which would feed it the very real values this capability exists to keep out.
try {
  const fs = require('fs');
  const path = require('path');
  const configPath = path.join(process.env.CLAUDE_PROJECT_DIR || process.cwd(), '.claude', 'redaction-config.json');
  if (fs.existsSync(configPath)) {
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const toInt = (s) => { const p = s.split('.').map(Number); return ((p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]) >>> 0; };
    const found = prompt.match(/\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/g) || [];
    const flagged = [];
    for (const cidrStr of config.cidrs || []) {
      const [ip, prefixStr] = cidrStr.split('/');
      const prefixLen = Number(prefixStr);
      const mask = prefixLen === 0 ? 0 : (0xffffffff << (32 - prefixLen)) >>> 0;
      const network = toInt(ip) & mask;
      for (const m of found) {
        if ((toInt(m) & mask) === network) flagged.push(m);
      }
    }
    for (const suffix of config.domains || []) {
      if (lower.includes(suffix.toLowerCase())) flagged.push(suffix);
    }
    if (flagged.length > 0) {
      process.stdout.write(JSON.stringify({
        systemMessage: `Note: this prompt contains real configured infra value(s) (${[...new Set(flagged)].join(', ')}) from .claude/redaction-config.json — Claude will see them in cleartext for this turn. Non-blocking.`,
      }));
    }
  }
} catch { /* fail open — never let the redaction check block a legitimate prompt */ }

process.exit(0);
```

<!-- ref: add/redaction/hook-python.md
     loaded-by: add/redaction/implementation.md → add/SKILL.md
     prereq: Stack is FastAPI (Python hook runtime); add (redaction) Steps 0–2 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Redaction hooks — Python runtime (FastAPI)

**Part A** (masking hook) applies at implementation.md Step 3; **Part B** (`user-prompt-guard` warning) at Step 6.

### Part A — `PostToolUse` masking hook

Run `TC_PART=leaf TC_LEAF=add/redaction/hook-python bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/redaction/hook-python/template/` (listed in `<skill-dir>/redaction/hook-python/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

The hook for FastAPI is `.claude/hooks/redact_sensitive_output.py` (copied above):

Copied verbatim from `<skill-dir>/redaction/hook-python/template/.claude/hooks/redact_sensitive_output.py` by the copy step; do not re-type it.

### Part B — `user-prompt-guard` companion warning

**For FastAPI** — in `.claude/hooks/user-prompt-guard.py`, insert immediately before the final
`sys.exit(0)`:

```python
# Redaction companion (OWASP LLM02 infra-topology variant) -- only active if add (redaction) has been applied.
# Warns, never blocks: the human is the one party allowed to reference real infra values.
# The warning goes out as `systemMessage`, a human-facing surface. It must NOT go to plain
# stdout or additionalContext: on UserPromptSubmit those can be injected into the model's
# context, which would feed it the very real values this capability exists to keep out.
try:
    import os
    config_path = os.path.join(os.environ.get('CLAUDE_PROJECT_DIR') or os.getcwd(), '.claude', 'redaction-config.json')
    if os.path.exists(config_path):
        with open(config_path) as f:
            config = json.load(f)
        ipv4_re = re.compile(r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b')
        found = ipv4_re.findall(prompt)
        def to_int(s):
            p = [int(x) for x in s.split('.')]
            return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]
        flagged = []
        for cidr_str in config.get('cidrs') or []:
            ip, prefix_str = cidr_str.split('/')
            prefix_len = int(prefix_str)
            mask = 0 if prefix_len == 0 else (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF
            network = to_int(ip) & mask
            for m in found:
                if (to_int(m) & mask) == network:
                    flagged.append(m)
        for suffix in config.get('domains') or []:
            if suffix.lower() in lower:
                flagged.append(suffix)
        if flagged:
            unique = ', '.join(dict.fromkeys(flagged))
            sys.stdout.write(json.dumps({'systemMessage':
                f'Note: this prompt contains real configured infra value(s) ({unique}) from '
                '.claude/redaction-config.json -- Claude will see them in cleartext for this turn. '
                'Non-blocking.'}, separators=(',', ':')))
except Exception:
    pass  # fail open -- never let the redaction check block a legitimate prompt

sys.exit(0)
```

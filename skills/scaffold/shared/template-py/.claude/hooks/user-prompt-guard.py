#!/usr/bin/env python3
# UserPromptSubmit — OWASP LLM01 injection guard + LLM02 credential-leak detection. Exit 2 = block.
import json
import re
import sys

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
db_url = re.compile(r'(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp)://[^:/\s@]*:[^@\s/]+@(\[[^\]\s]*\]|[^/:\s?#,]+)', re.IGNORECASE)
loopback = {'localhost', '127.0.0.1', '[::1]'}
for m in db_url.finditer(prompt):
    if m.group(4).lower() not in loopback:
        sys.stderr.write('Blocked: prompt may contain a real credential — database/broker URL with embedded credentials (OWASP LLM02). Do not paste secrets; use env vars.\n')
        sys.exit(2)
sys.exit(0)

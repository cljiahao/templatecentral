#!/usr/bin/env node
// UserPromptSubmit — OWASP LLM01 injection guard + LLM02 credential-leak detection. Exit 2 = block.
const input = require('fs').readFileSync(0, 'utf8');
let prompt = '';
try { prompt = (JSON.parse(input || '{}').prompt) || ''; } catch { process.exit(0); }
const lower = prompt.toLowerCase();

const injection = [
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
];
// "disregard/override your …" only when the object is the agent's own instructions —
// "override your config defaults" is an ordinary engineering request.
const injectionRe = /\b(disregard|override)\s+(all\s+)?(of\s+)?your\s+((previous|prior|original|current)\s+)?(instructions|rules|system\s+prompt|guidelines)\b/;
const hit = injection.find((p) => lower.includes(p)) || (lower.match(injectionRe) || [])[0];
if (hit) {
  process.stderr.write(`Blocked: prompt matches an injection pattern (OWASP LLM01): "${hit}"\n`);
  process.exit(2);
}

const credentials = [
  [/AKIA[0-9A-Z]{16}/, 'AWS access key ID'],
  [/ghp_[A-Za-z0-9]{36}/, 'GitHub personal access token'],
  [/github_pat_[A-Za-z0-9_]{82}/, 'GitHub fine-grained PAT'],
  [/sk-ant-[A-Za-z0-9\-_]{90,}/, 'Anthropic API key'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'PEM private key block'],
];
for (const [re, label] of credentials) {
  if (re.test(prompt)) {
    process.stderr.write(`Blocked: prompt may contain a real credential — ${label} (OWASP LLM02). Do not paste secrets; use env vars.\n`);
    process.exit(2);
  }
}
// DB/broker URL with embedded user:password — loopback hosts (local dev defaults) are exempt.
const dbUrl = /(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp):\/\/[^:\/\s@]*:[^@\s\/]+@(\[[^\]\s]*\]|[^\/:\s?#,]+)/gi;
const loopback = new Set(['localhost', '127.0.0.1', '[::1]']);
for (const m of prompt.matchAll(dbUrl)) {
  if (!loopback.has(m[4].toLowerCase())) {
    process.stderr.write('Blocked: prompt may contain a real credential — database/broker URL with embedded credentials (OWASP LLM02). Do not paste secrets; use env vars.\n');
    process.exit(2);
  }
}
process.exit(0);

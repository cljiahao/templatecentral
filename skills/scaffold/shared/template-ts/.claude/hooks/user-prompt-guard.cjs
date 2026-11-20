#!/usr/bin/env node
// Blocks a prompt that carries a real credential; no injection phrase list, since injected text arrives through tool output this hook never sees.
const input = require('fs').readFileSync(0, 'utf8');
let prompt = '';
try { prompt = (JSON.parse(input || '{}').prompt) || ''; } catch { process.exit(0); }

const credentials = [
  [/AKIA[0-9A-Z]{16}/, 'AWS access key ID'],
  [/ghp_[A-Za-z0-9]{36}/, 'GitHub personal access token'],
  [/github_pat_[A-Za-z0-9_]{82}/, 'GitHub fine-grained PAT'],
  [/sk-ant-[A-Za-z0-9\-_]{90,}/, 'Anthropic API key'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'PEM private key block'],
];
for (const [re, label] of credentials) {
  if (re.test(prompt)) {
    process.stderr.write(`Blocked: your prompt looks like it contains a ${label}. Nothing was sent to the model. Remove the value and send it again; refer to it by the environment variable name (the value lives only in your own untracked .env). If it is a live credential, rotate it.\n`);
    process.exit(2);
  }
}
// DB/broker URL with embedded user:password; loopback hosts are exempt as local-dev defaults.
const dbUrl = /(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp):\/\/[^:\/\s@]*:[^@\s\/]+@(\[[^\]\s]*\]|[^\/:\s?#,]+)/gi;
const loopback = new Set(['localhost', '127.0.0.1', '[::1]']);
for (const m of prompt.matchAll(dbUrl)) {
  if (!loopback.has(m[4].toLowerCase())) {
    process.stderr.write('Blocked: your prompt looks like it contains a database or broker URL with an embedded password. Nothing was sent to the model. Replace the URL with the environment variable name (DATABASE_URL) and send it again; if it is a live credential, rotate it.\n');
    process.exit(2);
  }
}
process.exit(0);

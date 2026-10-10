<!-- ref: add/redaction/hook-node.md
     loaded-by: add/redaction/implementation.md → add/SKILL.md
     prereq: Stack is NestJS, Next.js, or Vite + React (Node hook runtime); add (redaction) Steps 0–2 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Redaction hooks — Node runtime (TS stacks)

Contents: **Part A** — the `PostToolUse` masking hook (implementation.md Step 3). **Part B** — the `user-prompt-guard` companion warning (implementation.md Step 6). Apply Part A now, then continue implementation.md at Step 4; apply Part B when it reaches Step 6.

### Part A — `PostToolUse` masking hook

**For TS stacks (nestjs / nextjs / vite-react)** — write `.claude/hooks/redact-sensitive-output.cjs`:

```javascript
#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const PROJECT_DIR = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const CONFIG_PATH = path.join(PROJECT_DIR, '.claude', 'redaction-config.json');
const MAP_PATH = path.join(PROJECT_DIR, '.claude', '.redaction-map.json');
// Synthetic address spaces, tried in order. 10.0.0.0/8 is RFC 1918 private-use;
// 198.18.0.0/15 is the RFC 2544 benchmarking range -- standards-reserved and
// essentially never used for real internal infra, so it is the fallback whenever a
// configured real range overlaps the primary space (masking into a block that
// overlaps the real one would emit the real value back out).
const SYNTHETIC_SPACES = ['10.0.0.0/8', '198.18.0.0/15'];
const DOMAIN_SUFFIX = 'example'; // RFC 2606 reserved
const CIDR_RE = /^\d{1,3}(?:\.\d{1,3}){3}\/\d{1,2}$/;
const IPV4_RE = /\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/g;

function ipToInt(ip) {
  const parts = ip.split('.').map(Number);
  return ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) >>> 0;
}

function intToIp(int) {
  return [24, 16, 8, 0].map((shift) => (int >>> shift) & 0xff).join('.');
}

function maskFor(prefixLen) {
  if (prefixLen === 0) return 0;
  return (0xffffffff << (32 - prefixLen)) >>> 0;
}

function blockSize(prefixLen) {
  return 2 ** (32 - prefixLen);
}

function parseCidr(cidrStr) {
  const [ip, prefixStr] = cidrStr.split('/');
  const prefixLen = Number(prefixStr);
  const mask = maskFor(prefixLen);
  const network = ipToInt(ip) & mask;
  return { network, prefixLen, mask };
}

function cidrContains(cidr, ipInt) {
  return (ipInt & cidr.mask) === cidr.network;
}

function cidrsOverlap(a, b) {
  return a.network < b.network + blockSize(b.prefixLen) && b.network < a.network + blockSize(a.prefixLen);
}

function loadJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function normalizeMap(raw) {
  const map = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const offsets = Array.isArray(map.nextCidrOffsets) ? map.nextCidrOffsets : [];
  return {
    cidrs: map.cidrs && typeof map.cidrs === 'object' ? map.cidrs : {},
    domains: map.domains && typeof map.domains === 'object' ? map.domains : {},
    nextCidrOffsets: SYNTHETIC_SPACES.map((_, i) => Number(offsets[i]) || 0),
    nextDomainIndex: Number(map.nextDomainIndex) || 0,
  };
}

function emptyMap() {
  return normalizeMap(null);
}

// Keeps assignments another concurrent invocation may have persisted since this run
// read the map, adding only the keys this run allocated. Combined with the temp-file
// + rename(2) write below (atomic, so no reader ever sees a partial map) this narrows
// -- it does not fully close -- the read/modify/write race between parallel tool calls.
function mergeMaps(base, ours) {
  return {
    cidrs: { ...ours.cidrs, ...base.cidrs },
    domains: { ...ours.domains, ...base.domains },
    nextCidrOffsets: SYNTHETIC_SPACES.map((_, i) => Math.max(base.nextCidrOffsets[i], ours.nextCidrOffsets[i])),
    nextDomainIndex: Math.max(base.nextDomainIndex, ours.nextDomainIndex),
  };
}

function saveMapAtomic(filePath, map) {
  let onDisk = null;
  try {
    onDisk = loadJson(filePath, null);
  } catch (err) {
    onDisk = null;
  }
  const merged = mergeMaps(normalizeMap(onDisk), map);
  const tmpPath = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(merged, null, 2) + '\n', 'utf8');
  fs.renameSync(tmpPath, filePath);
}

// Returns a human-readable problem description, or null when the config is usable.
// A malformed entry must never be silently ignored: a CIDR that does not parse would
// otherwise disable masking for that range without anyone noticing.
function validateConfig(config) {
  if (config === null || typeof config !== 'object' || Array.isArray(config)) {
    return 'top-level value must be a JSON object';
  }
  for (const key of ['cidrs', 'domains']) {
    if (config[key] === undefined || config[key] === null) continue;
    if (!Array.isArray(config[key])) return `"${key}" must be an array of strings`;
    for (const entry of config[key]) {
      if (typeof entry !== 'string' || entry.length === 0) {
        return `"${key}" must contain only non-empty strings (found ${JSON.stringify(entry)})`;
      }
    }
  }
  for (const cidr of config.cidrs || []) {
    if (!CIDR_RE.test(cidr)) return `"${cidr}" is not a valid IPv4 CIDR (expected a.b.c.d/prefix)`;
    const [ip, prefixStr] = cidr.split('/');
    const prefixLen = Number(prefixStr);
    if (!Number.isInteger(prefixLen) || prefixLen < 0 || prefixLen > 32) {
      return `"${cidr}" has an out-of-range prefix length (must be 0-32)`;
    }
    for (const octet of ip.split('.')) {
      const value = Number(octet);
      if (!Number.isInteger(value) || value < 0 || value > 255) {
        return `"${cidr}" has an out-of-range octet "${octet}" (must be 0-255)`;
      }
    }
  }
  return null;
}

// Allocates an alignment-correct synthetic block that overlaps neither a previously
// allocated synthetic block nor ANY configured real range. A synthetic space that any
// configured real range touches is disqualified wholesale: allocating from it risks
// handing back the real value as its own "mask", which reports success while leaking.
// Larger real blocks (a short prefix such as /8 or shorter) claim a proportionally
// bigger share of a space, so they exhaust the available slots fastest; when no space
// can serve the request this throws rather than returning a colliding block.
function allocateSyntheticCidr(prefixLen, map, realCidrs) {
  const slotSize = blockSize(prefixLen);
  for (let i = 0; i < SYNTHETIC_SPACES.length; i += 1) {
    const space = parseCidr(SYNTHETIC_SPACES[i]);
    const spaceSize = blockSize(space.prefixLen);
    if (slotSize > spaceSize) continue;
    if (realCidrs.some((real) => cidrsOverlap(space, real))) continue;
    let offset = map.nextCidrOffsets[i];
    const remainder = offset % slotSize;
    if (remainder !== 0) offset += slotSize - remainder;
    if (offset + slotSize > spaceSize) continue;
    map.nextCidrOffsets[i] = offset + slotSize;
    return { network: (space.network + offset) >>> 0, prefixLen, mask: maskFor(prefixLen) };
  }
  throw new Error(
    `no synthetic /${prefixLen} block is available in ${SYNTHETIC_SPACES.join(' or ')} that is disjoint from the configured real ranges -- declare narrower real range(s) (a real range that swallows a whole synthetic space leaves nothing to mask into)`
  );
}

function getOrAssignMaskedCidr(realCidrStr, map, realCidrs) {
  const real = parseCidr(realCidrStr);
  const existing = map.cidrs[realCidrStr];
  if (existing) {
    const parsed = parseCidr(existing);
    if (parsed.network === real.network) {
      throw new Error(`persisted synthetic block for ${realCidrStr} is identical to the real block`);
    }
    return parsed;
  }
  const synthetic = allocateSyntheticCidr(real.prefixLen, map, realCidrs);
  if (synthetic.network === real.network) {
    throw new Error(`allocated synthetic block for ${realCidrStr} is identical to the real block`);
  }
  map.cidrs[realCidrStr] = `${intToIp(synthetic.network)}/${synthetic.prefixLen}`;
  return synthetic;
}

function getOrAssignMaskedDomain(realSuffix, map) {
  const key = realSuffix.toLowerCase();
  if (map.domains[key]) return map.domains[key];
  const synthetic = `masked${map.nextDomainIndex}.${DOMAIN_SUFFIX}`;
  map.domains[key] = synthetic;
  map.nextDomainIndex += 1;
  return synthetic;
}

function maskIps(text, cidrStrs, map) {
  let count = 0;
  const realCidrs = cidrStrs.map(parseCidr);
  const masked = text.replace(IPV4_RE, (match) => {
    const ipInt = ipToInt(match);
    for (let i = 0; i < cidrStrs.length; i += 1) {
      if (cidrContains(realCidrs[i], ipInt)) {
        const synthetic = getOrAssignMaskedCidr(cidrStrs[i], map, realCidrs);
        const hostBits = ipInt & ~synthetic.mask;
        const maskedInt = (hostBits | synthetic.network) >>> 0;
        count += 1;
        return intToIp(maskedInt);
      }
    }
    return match;
  });
  return { text: masked, count };
}

function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function maskDomains(text, domainSuffixes, map) {
  let count = 0;
  let masked = text;
  // Longest suffix first so overlapping entries (e.g. "internal" and "corp.internal")
  // do not collapse into the shorter one depending on config order.
  const ordered = [...domainSuffixes].sort((a, b) => b.length - a.length);
  for (const suffix of ordered) {
    const re = new RegExp(`\\b(?:[\\w-]+\\.)*${escapeRegExp(suffix)}\\b`, 'gi');
    masked = masked.replace(re, (match) => {
      const synthetic = getOrAssignMaskedDomain(suffix, map);
      const prefixLen = match.length - suffix.length;
      count += 1;
      return match.slice(0, prefixLen) + synthetic;
    });
  }
  return { text: masked, count };
}

function redact(text, config, map) {
  const ipResult = maskIps(text, config.cidrs || [], map);
  const domainResult = maskDomains(ipResult.text, config.domains || [], map);
  return { text: domainResult.text, count: ipResult.count + domainResult.count };
}

// Built-in tools return structured output (Bash yields {stdout, stderr, interrupted,
// isImage}), and `updatedToolOutput` must have the SAME shape as the tool produced --
// a flat string is silently discarded and the model sees the unmasked original. Walk
// whatever shape arrived and mask every string leaf in place, so this stays correct
// for all four matched tools and for any future change to their output shape.
function redactValue(value, config, map) {
  if (typeof value === 'string') {
    const result = redact(value, config, map);
    return { value: result.text, count: result.count };
  }
  if (Array.isArray(value)) {
    let count = 0;
    const out = value.map((item) => {
      const result = redactValue(item, config, map);
      count += result.count;
      return result.value;
    });
    return { value: out, count };
  }
  if (value !== null && typeof value === 'object') {
    let count = 0;
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      const result = redactValue(item, config, map);
      count += result.count;
      out[key] = result.value;
    }
    return { value: out, count };
  }
  return { value, count: 0 };
}

function warnAndExit(message) {
  // Fail-open warning. Plain stderr on exit 0 reaches only the debug log -- neither the user nor
  // Claude sees it -- so the warning goes out as a `systemMessage` (shown to the user) while the
  // stderr copy keeps the debug log useful. Exit 0: the hook never blocks a tool call.
  process.stderr.write(`${message}\n`);
  process.stdout.write(JSON.stringify({ systemMessage: message }));
  process.exit(0);
}

function main() {
  if (!fs.existsSync(CONFIG_PATH)) process.exit(0);

  let config;
  try {
    config = loadJson(CONFIG_PATH, null);
  } catch (err) {
    warnAndExit(`redact-sensitive-output: malformed ${CONFIG_PATH} -- skipping this pass: ${err.message}`);
  }

  const problem = validateConfig(config);
  if (problem) {
    warnAndExit(`redact-sensitive-output: invalid ${CONFIG_PATH} -- skipping this pass: ${problem}`);
  }

  let input;
  try {
    input = JSON.parse(fs.readFileSync(0, 'utf8'));
  } catch (err) {
    process.exit(0);
  }

  let map;
  try {
    map = normalizeMap(loadJson(MAP_PATH, null));
  } catch (err) {
    map = emptyMap();
  }

  // Build the whole synthetic address plan up front so an unsatisfiable configuration
  // surfaces here -- at load time, named -- instead of deep inside the masking path.
  try {
    const realCidrs = (config.cidrs || []).map(parseCidr);
    for (const cidrStr of config.cidrs || []) getOrAssignMaskedCidr(cidrStr, map, realCidrs);
  } catch (err) {
    warnAndExit(
      `redact-sensitive-output: cannot build a synthetic address plan for ${CONFIG_PATH} -- skipping this pass: ${err.message}`
    );
  }

  let redacted;
  try {
    redacted = redactValue(input.tool_response === undefined ? '' : input.tool_response, config, map);
  } catch (err) {
    warnAndExit(`redact-sensitive-output: redaction failed -- leaving this output unmasked: ${err.message}`);
  }

  if (redacted.count === 0) process.exit(0);

  try {
    fs.mkdirSync(path.dirname(MAP_PATH), { recursive: true });
    saveMapAtomic(MAP_PATH, map);
  } catch (err) {
    warnAndExit(`redact-sensitive-output: could not persist ${MAP_PATH} -- leaving this output unmasked: ${err.message}`);
  }

  const output = {
    hookSpecificOutput: {
      hookEventName: 'PostToolUse',
      updatedToolOutput: redacted.value,
      additionalContext: `${redacted.count} value(s) in this output were masked per .claude/redaction-config.json. Do not attempt to infer or troubleshoot the real values -- hand IP/network-level troubleshooting to the human operator.`,
    },
  };
  process.stdout.write(JSON.stringify(output));
  process.exit(0);
}

if (require.main === module) {
  main();
}

module.exports = {
  ipToInt,
  intToIp,
  maskFor,
  blockSize,
  parseCidr,
  cidrContains,
  cidrsOverlap,
  validateConfig,
  allocateSyntheticCidr,
  getOrAssignMaskedCidr,
  getOrAssignMaskedDomain,
  maskIps,
  maskDomains,
  redact,
  redactValue,
  normalizeMap,
  emptyMap,
};
```

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

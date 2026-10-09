<!-- ref: add/redaction/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack identified; project already has the templateCentral harness seeded (scaffold or migrate). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

## Step 0 — Verify context

Confirm `.claude/settings.json` and `.claude/hooks/user-prompt-guard.cjs` (TS stacks) or
`.claude/hooks/user-prompt-guard.py` (FastAPI) already exist — this capability extends the existing
harness rather than creating one from scratch. If they don't exist, invoke `templatecentral:migrate`
first (Project-migration path), then re-check.

## Step 1 — Collect real values from the user

Ask the user for their project's real infrastructure values:

1. Real internal CIDR range(s) they want masked, e.g. `172.18.161.0/24`. IPv4 only.
2. Real internal domain suffix(es) they want masked, e.g. `corp.internal`.

At least one CIDR or one domain suffix is required — if the user has neither yet (a brand-new project
with no deployed infra), tell them to come back and run this capability once they do; there's nothing
to configure yet.

Ask for the **narrowest** ranges that actually cover their infra (the `/16`s or `/24`s in use), not a
blanket supernet. Masking works by mapping each real range onto a same-sized synthetic block drawn from
a reserved space that must stay disjoint from every declared real range; a range large enough to swallow
an entire synthetic space (a full `10.0.0.0/8`, say) leaves no disjoint block to map onto, and the hook
will refuse to mask rather than emit a value identical to the real one.

## Step 2 — Write `.claude/redaction-config.json`

Substitute the user's real values for the example below (JSON, not YAML — both hook runtimes parse it
with zero added dependencies):

```json
{
  "cidrs": ["172.18.161.0/24"],
  "domains": ["corp.internal"]
}
```

The companion mapping file (`.claude/.redaction-map.json`, created on first mask) is gitignored in
Step 7, so each teammate's machine allocates its own synthetic numbering independently — `masked0` and
`10.0.0.x` mean the same real value within one checkout, not across a team.

## Step 3 — Seed the `PostToolUse` hook

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
    redacted = redactValue(input.tool_output === undefined ? '' : input.tool_output, config, map);
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

**For FastAPI** — write `.claude/hooks/redact_sensitive_output.py`:

```python
#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(os.environ.get('CLAUDE_PROJECT_DIR') or Path.cwd())
CONFIG_PATH = PROJECT_DIR / '.claude' / 'redaction-config.json'
MAP_PATH = PROJECT_DIR / '.claude' / '.redaction-map.json'
# Synthetic address spaces, tried in order. 10.0.0.0/8 is RFC 1918 private-use;
# 198.18.0.0/15 is the RFC 2544 benchmarking range -- standards-reserved and
# essentially never used for real internal infra, so it is the fallback whenever a
# configured real range overlaps the primary space (masking into a block that
# overlaps the real one would emit the real value back out).
SYNTHETIC_SPACES = ['10.0.0.0/8', '198.18.0.0/15']
DOMAIN_SUFFIX = 'example'  # RFC 2606 reserved

CIDR_RE = re.compile(r'^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$')
IPV4_RE = re.compile(
    r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b'
)


# Hand-rolled rather than `ipaddress` so this agrees byte-for-byte with the Node
# runtime, including octets written with a leading zero ("172.18.161.05"), which
# `ipaddress.IPv4Address` rejects outright. Masking such a candidate is the safer
# default for a security control than passing it through untouched.
def ip_to_int(ip_str):
    parts = [int(part) for part in ip_str.split('.')]
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]


def int_to_ip(value):
    return '.'.join(str((value >> shift) & 0xFF) for shift in (24, 16, 8, 0))


def mask_for(prefix_len):
    if prefix_len == 0:
        return 0
    return (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF


def block_size(prefix_len):
    return 1 << (32 - prefix_len)


def parse_cidr(cidr_str):
    ip_str, prefix_str = cidr_str.split('/')
    prefix_len = int(prefix_str)
    mask = mask_for(prefix_len)
    network = ip_to_int(ip_str) & mask
    return {'network': network, 'prefixLen': prefix_len, 'mask': mask}


def cidr_contains(cidr, ip_int):
    return (ip_int & cidr['mask']) == cidr['network']


def cidrs_overlap(a, b):
    return (
        a['network'] < b['network'] + block_size(b['prefixLen'])
        and b['network'] < a['network'] + block_size(a['prefixLen'])
    )


def load_json(path, fallback):
    if not path.exists():
        return fallback
    return json.loads(path.read_text())


def normalize_map(raw):
    source = raw if isinstance(raw, dict) else {}
    offsets = source.get('nextCidrOffsets')
    if not isinstance(offsets, list):
        offsets = []
    return {
        'cidrs': source['cidrs'] if isinstance(source.get('cidrs'), dict) else {},
        'domains': source['domains'] if isinstance(source.get('domains'), dict) else {},
        'nextCidrOffsets': [
            int(offsets[i]) if i < len(offsets) and isinstance(offsets[i], int) else 0
            for i in range(len(SYNTHETIC_SPACES))
        ],
        'nextDomainIndex': source['nextDomainIndex'] if isinstance(source.get('nextDomainIndex'), int) else 0,
    }


def empty_map():
    return normalize_map(None)


# Keeps assignments another concurrent invocation may have persisted since this run
# read the map, adding only the keys this run allocated. Combined with the temp-file
# + atomic replace below (no reader ever sees a partial map) this narrows -- it does
# not fully close -- the read/modify/write race between parallel tool calls.
def merge_maps(base, ours):
    cidrs = dict(ours['cidrs'])
    cidrs.update(base['cidrs'])
    domains = dict(ours['domains'])
    domains.update(base['domains'])
    return {
        'cidrs': cidrs,
        'domains': domains,
        'nextCidrOffsets': [
            max(base['nextCidrOffsets'][i], ours['nextCidrOffsets'][i])
            for i in range(len(SYNTHETIC_SPACES))
        ],
        'nextDomainIndex': max(base['nextDomainIndex'], ours['nextDomainIndex']),
    }


def save_map_atomic(path, redaction_map):
    try:
        on_disk = load_json(path, None)
    except (json.JSONDecodeError, OSError):
        on_disk = None
    merged = merge_maps(normalize_map(on_disk), redaction_map)
    tmp_path = path.with_name(f'{path.name}.{os.getpid()}.tmp')
    tmp_path.write_text(json.dumps(merged, indent=2) + '\n')
    os.replace(tmp_path, path)


# Returns a human-readable problem description, or None when the config is usable.
# A malformed entry must never be silently ignored: a CIDR that does not parse would
# otherwise disable masking for that range without anyone noticing.
def validate_config(config):
    if not isinstance(config, dict):
        return 'top-level value must be a JSON object'
    for key in ('cidrs', 'domains'):
        value = config.get(key)
        if value is None:
            continue
        if not isinstance(value, list):
            return f'"{key}" must be an array of strings'
        for entry in value:
            if not isinstance(entry, str) or not entry:
                return f'"{key}" must contain only non-empty strings (found {entry!r})'
    for cidr in config.get('cidrs') or []:
        if not CIDR_RE.match(cidr):
            return f'"{cidr}" is not a valid IPv4 CIDR (expected a.b.c.d/prefix)'
        ip_str, prefix_str = cidr.split('/')
        prefix_len = int(prefix_str)
        if prefix_len < 0 or prefix_len > 32:
            return f'"{cidr}" has an out-of-range prefix length (must be 0-32)'
        for octet in ip_str.split('.'):
            if int(octet) > 255:
                return f'"{cidr}" has an out-of-range octet "{octet}" (must be 0-255)'
    return None


# Allocates an alignment-correct synthetic block that overlaps neither a previously
# allocated synthetic block nor ANY configured real range. A synthetic space that any
# configured real range touches is disqualified wholesale: allocating from it risks
# handing back the real value as its own "mask", which reports success while leaking.
# Larger real blocks (a short prefix such as /8 or shorter) claim a proportionally
# bigger share of a space, so they exhaust the available slots fastest; when no space
# can serve the request this raises rather than returning a colliding block.
def allocate_synthetic_cidr(prefix_len, redaction_map, real_cidrs):
    slot_size = block_size(prefix_len)
    for i, space_str in enumerate(SYNTHETIC_SPACES):
        space = parse_cidr(space_str)
        space_size = block_size(space['prefixLen'])
        if slot_size > space_size:
            continue
        if any(cidrs_overlap(space, real) for real in real_cidrs):
            continue
        offset = redaction_map['nextCidrOffsets'][i]
        remainder = offset % slot_size
        if remainder != 0:
            offset += slot_size - remainder
        if offset + slot_size > space_size:
            continue
        redaction_map['nextCidrOffsets'][i] = offset + slot_size
        return {
            'network': space['network'] + offset,
            'prefixLen': prefix_len,
            'mask': mask_for(prefix_len),
        }
    raise ValueError(
        f'no synthetic /{prefix_len} block is available in {" or ".join(SYNTHETIC_SPACES)} '
        'that is disjoint from the configured real ranges -- declare narrower real range(s) '
        '(a real range that swallows a whole synthetic space leaves nothing to mask into)'
    )


def get_or_assign_masked_cidr(real_cidr_str, redaction_map, real_cidrs):
    real = parse_cidr(real_cidr_str)
    existing = redaction_map['cidrs'].get(real_cidr_str)
    if existing:
        parsed = parse_cidr(existing)
        if parsed['network'] == real['network']:
            raise ValueError(f'persisted synthetic block for {real_cidr_str} is identical to the real block')
        return parsed
    synthetic = allocate_synthetic_cidr(real['prefixLen'], redaction_map, real_cidrs)
    if synthetic['network'] == real['network']:
        raise ValueError(f'allocated synthetic block for {real_cidr_str} is identical to the real block')
    redaction_map['cidrs'][real_cidr_str] = f"{int_to_ip(synthetic['network'])}/{synthetic['prefixLen']}"
    return synthetic


def get_or_assign_masked_domain(real_suffix, redaction_map):
    key = real_suffix.lower()
    existing = redaction_map['domains'].get(key)
    if existing:
        return existing
    synthetic = f"masked{redaction_map['nextDomainIndex']}.{DOMAIN_SUFFIX}"
    redaction_map['domains'][key] = synthetic
    redaction_map['nextDomainIndex'] += 1
    return synthetic


def mask_ips(text, cidr_strs, redaction_map):
    count = 0
    real_cidrs = [parse_cidr(c) for c in cidr_strs]

    def replace(match):
        nonlocal count
        ip_int = ip_to_int(match.group(0))
        for cidr_str, parsed in zip(cidr_strs, real_cidrs):
            if cidr_contains(parsed, ip_int):
                synthetic = get_or_assign_masked_cidr(cidr_str, redaction_map, real_cidrs)
                host_bits = ip_int & (~synthetic['mask'] & 0xFFFFFFFF)
                masked_int = (host_bits | synthetic['network']) & 0xFFFFFFFF
                count += 1
                return int_to_ip(masked_int)
        return match.group(0)

    masked = IPV4_RE.sub(replace, text)
    return masked, count


def mask_domains(text, domain_suffixes, redaction_map):
    count = 0
    masked = text
    # Longest suffix first so overlapping entries (e.g. "internal" and "corp.internal")
    # do not collapse into the shorter one depending on config order.
    for suffix in sorted(domain_suffixes, key=len, reverse=True):
        pattern = re.compile(r'\b(?:[\w-]+\.)*' + re.escape(suffix) + r'\b', re.IGNORECASE)

        def replace(match, suffix=suffix):
            nonlocal count
            synthetic = get_or_assign_masked_domain(suffix, redaction_map)
            prefix_len = len(match.group(0)) - len(suffix)
            count += 1
            return match.group(0)[:prefix_len] + synthetic

        masked = pattern.sub(replace, masked)
    return masked, count


def redact(text, config, redaction_map):
    text, ip_count = mask_ips(text, config.get('cidrs') or [], redaction_map)
    text, domain_count = mask_domains(text, config.get('domains') or [], redaction_map)
    return text, ip_count + domain_count


# Built-in tools return structured output (Bash yields {stdout, stderr, interrupted,
# isImage}), and `updatedToolOutput` must have the SAME shape as the tool produced --
# a flat string is silently discarded and the model sees the unmasked original. Walk
# whatever shape arrived and mask every string leaf in place, so this stays correct
# for all four matched tools and for any future change to their output shape.
def redact_value(value, config, redaction_map):
    if isinstance(value, str):
        return redact(value, config, redaction_map)
    if isinstance(value, list):
        count = 0
        out = []
        for item in value:
            masked_item, item_count = redact_value(item, config, redaction_map)
            count += item_count
            out.append(masked_item)
        return out, count
    if isinstance(value, dict):
        count = 0
        out = {}
        for key, item in value.items():
            masked_item, item_count = redact_value(item, config, redaction_map)
            count += item_count
            out[key] = masked_item
        return out, count
    return value, 0


def warn_and_exit(message):
    # Fail-open warning. Plain stderr on exit 0 reaches only the debug log -- neither the user
    # nor Claude sees it -- so the warning goes out as a `systemMessage` (shown to the user)
    # while the stderr copy keeps the debug log useful. Exit 0: the hook never blocks a tool call.
    sys.stderr.write(f'{message}\n')
    sys.stdout.write(json.dumps({'systemMessage': message}, separators=(',', ':')))
    sys.exit(0)


def main():
    if not CONFIG_PATH.exists():
        sys.exit(0)

    try:
        config = load_json(CONFIG_PATH, None)
    except (json.JSONDecodeError, OSError) as err:
        warn_and_exit(f'redact-sensitive-output: malformed {CONFIG_PATH} -- skipping this pass: {err}')

    problem = validate_config(config)
    if problem:
        warn_and_exit(f'redact-sensitive-output: invalid {CONFIG_PATH} -- skipping this pass: {problem}')

    try:
        input_data = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, OSError):
        sys.exit(0)

    try:
        redaction_map = normalize_map(load_json(MAP_PATH, None))
    except (json.JSONDecodeError, OSError):
        redaction_map = empty_map()

    # Build the whole synthetic address plan up front so an unsatisfiable configuration
    # surfaces here -- at load time, named -- instead of deep inside the masking path.
    try:
        real_cidrs = [parse_cidr(c) for c in config.get('cidrs') or []]
        for cidr_str in config.get('cidrs') or []:
            get_or_assign_masked_cidr(cidr_str, redaction_map, real_cidrs)
    except ValueError as err:
        warn_and_exit(
            f'redact-sensitive-output: cannot build a synthetic address plan for {CONFIG_PATH} '
            f'-- skipping this pass: {err}'
        )

    try:
        masked_output, count = redact_value(input_data.get('tool_output', ''), config, redaction_map)
    except Exception as err:
        warn_and_exit(f'redact-sensitive-output: redaction failed -- leaving this output unmasked: {err}')

    if count == 0:
        sys.exit(0)

    try:
        MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
        save_map_atomic(MAP_PATH, redaction_map)
    except OSError as err:
        warn_and_exit(f'redact-sensitive-output: could not persist {MAP_PATH} -- leaving this output unmasked: {err}')

    output = {
        'hookSpecificOutput': {
            'hookEventName': 'PostToolUse',
            'updatedToolOutput': masked_output,
            'additionalContext': (
                f'{count} value(s) in this output were masked per .claude/redaction-config.json. '
                'Do not attempt to infer or troubleshoot the real values -- hand IP/network-level '
                'troubleshooting to the human operator.'
            ),
        }
    }
    # Compact separators so this runtime's stdout is byte-identical to the Node one.
    sys.stdout.write(json.dumps(output, separators=(',', ':')))
    sys.exit(0)


if __name__ == '__main__':
    main()
```

## Step 4 — Wire the hook into `.claude/settings.json`

Merge this entry into the existing `hooks.PostToolUse` array (do not overwrite other entries — same
merge convention as `harness-kit.md` Step A):

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

This is load-bearing: the config/map files contain the real values in plaintext. If the agent can read
them directly, the hook's masking is pointless — the agent already has the real values from the config
file itself.

Scope of that deny: it covers the `Read` tool and the file-reading Bash commands Claude Code recognises
(`cat`, `head`, `tail`, …), but not an arbitrary subprocess that happens to read the file
(`python -c`, `node -e`, a script). Treat it as a strong deterrent against casual access, not an
OS-level guarantee.

## Step 5 — Extend `protect-files.sh`

Give the two redaction files their own case arm in `.claude/hooks/protect-files.sh` (human approval
required before write) — add it alongside the existing `.claude/hooks/*` and `.claude/harness.json`
arms, not folded into them, so the approval prompt states the real reason:

```bash
  .claude/redaction-config.json|*/.claude/redaction-config.json|.claude/.redaction-map.json|*/.claude/.redaction-map.json) reason="redaction policy config — editing it can weaken or disable masking of real infra data" ;;
```

## Step 6 — Add the companion warning to `user-prompt-guard`

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

## Step 7 — Gitignore the map file

Add this line to `.gitignore` if not already present:

```
.claude/.redaction-map.json
```

The config file (`.claude/redaction-config.json`) is NOT gitignored — it's meant to be committed so the
team shares the same masking policy; only the accumulated real→synthetic mapping is local/sensitive
enough to exclude from history.

## Step 8 — Re-bless the harness-integrity baseline

This capability edits `.claude/settings.json` and `.claude/hooks/*`, both of which `verify-harness.sh`
hashes against `.claude/harness.json` — a hard CI gate and a pre-push lefthook hook. Until the baseline
is refreshed, every push will fail on drift. Tell the user (do NOT run it as the agent — re-blessing is
a human act, and `protect-files.sh` gates `harness.json` for exactly this reason):

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
echo '{"tool_output":{"stdout":"host at <a real IP from the configured range>","stderr":"","interrupted":false}}' \
  | node .claude/hooks/redact-sensitive-output.cjs   # FastAPI: python3 .claude/hooks/redact_sensitive_output.py
```

The last check must print an `updatedToolOutput` **object** (`{"stdout":...,"stderr":"","interrupted":false}`)
with the real IP replaced — a flat string there would be silently discarded by Claude Code for built-in
tools, leaving the output unmasked.

Capability is complete once all five checks pass.

## Scope and limitations

- **Tool coverage.** The `Bash|Read|Grep|Glob` matcher is the v1 scope boundary, deliberately chosen
  because those four are where infra data surfaces in practice. `WebFetch`, MCP tool results, and
  subagent/`Task` output are NOT masked — treat them as unprotected surfaces, not as an oversight.
- **Range sizing.** A declared real range that covers an entire synthetic space has no disjoint block to
  map onto; the hook emits a named warning (as a user-facing `systemMessage`) and passes the output through unmasked rather than
  emitting a "mask" identical to the input. Declare narrower ranges (see Step 1).
- **Fail-open by design.** Malformed config, invalid CIDR entries, an unsatisfiable address plan, or any
  unexpected error during masking all produce a `systemMessage` warning (plain stderr on exit 0 would
  reach only the debug log) and exit 0. The hook never blocks a tool
  call; a broken redaction config degrades to no masking, visibly, not to a stalled session.

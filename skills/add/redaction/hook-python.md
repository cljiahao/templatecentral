<!-- ref: add/redaction/hook-python.md
     loaded-by: add/redaction/implementation.md → add/SKILL.md
     prereq: Stack is FastAPI (Python hook runtime); add (redaction) Steps 0–2 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Redaction hooks — Python runtime (FastAPI)

Contents: **Part A** — the `PostToolUse` masking hook (implementation.md Step 3). **Part B** — the `user-prompt-guard` companion warning (implementation.md Step 6). Apply Part A now, then continue implementation.md at Step 4; apply Part B when it reaches Step 6.

### Part A — `PostToolUse` masking hook

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
        masked_output, count = redact_value(input_data.get('tool_response', ''), config, redaction_map)
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

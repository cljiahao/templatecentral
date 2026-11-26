#!/usr/bin/env bash
# scripts/seeded-lock-parser-fuzz.test.sh — the seeded lock parser (py-env.py wanted) against pip's own requirements parser on generated lock files.
# Fixed seed, so every run is the same. It fails when the helper accepts a file in which pip sees a requirement the helper does not list, or sees a listed one without hashes.
# Local Python and its bundled pip only: no network, no install. If pip's parser cannot be imported it prints SKIP and exits 0, except when CI is set, where it exits 1.
# Usage: bash scripts/seeded-lock-parser-fuzz.test.sh        Env: PY_ENV_HELPER overrides the helper path, FUZZ_COUNT the number of files (default 4000).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER=${PY_ENV_HELPER:-$REPO_ROOT/skills/scaffold/shared/template/scripts/py-env.py}
COUNT=${FUZZ_COUNT:-4000}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-lock-fuzz.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

cat > "$T/fuzz.py" << 'PY'
import os
import random
import sys
import time

helper, count, workdir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
source = open(helper).read()
if "\nmain(sys.argv)\n" not in source:
    print("FAIL: the helper no longer ends with main(sys.argv), so it cannot be loaded as a module")
    sys.exit(1)
scope = {"__name__": "py_env_under_test"}
exec(compile(source.replace("\nmain(sys.argv)\n", "\n"), helper, "exec"), scope)
try:
    from pip import __version__ as pip_version
    from pip._internal.network.session import PipSession
    from pip._internal.req.req_file import parse_requirements
    from pip._vendor.packaging.requirements import Requirement
except Exception as e:
    print("SKIP: pip's requirements parser cannot be imported (%s)" % e)
    sys.exit(77)

rng = random.Random(20241120)
NAMES = ["foo", "bar", "Baz_Qux", "evil", "a.b", "x1"]
VERSIONS = ["1.0", "2.3.4", "0.1.dev1", "1!2.0"]
MARKERS = ["python_version<'3'", "sys_platform == 'win32'", "python_version >= '3.9'"]
OPTIONS = ["--require-hashes", "--index-url x", "-i x", "--extra-index-url x", "--find-links x", "-f x", "--no-binary :all:", "--only-binary :all:", "--trusted-host x", "--prefer-binary"]
TOKENS = NAMES + VERSIONS + ["==", "\\", "\n", "\r\n", "\r", " ", "  ", "\t", "--hash=sha256:aa", "--hash=sha256:bb", "-r x", "-c x", "-e .", ";", "#", "$", "${X}", "[x]", "@", "https://x/y.whl", "\x0c", "\x0b", "\x00", " ", "\xe9"] + MARKERS + [o.split()[0] for o in OPTIONS]


def req_block():
    """Returns a requirement line with hash continuations as uv writes them, with the join shape varied now and then."""
    line = rng.choice(NAMES) + rng.choice(["", "[x]"]) + "==" + rng.choice(VERSIONS)
    if rng.random() < 0.3:
        line += " ; " + rng.choice(MARKERS)
    join = rng.choice([" \\"] * 6 + ["\\", "\t\\", "  \\", " \t\\"])
    indent = rng.choice(["    "] * 6 + ["", " ", "\t", "  \t"])
    hashes = [indent + "--hash=sha256:" + rng.choice(["aa", "bb", "cc01"]) for _ in range(rng.choice([1, 1, 2, 3]))]
    out = [line + join]
    for i, h in enumerate(hashes):
        out.append(h + (join if i < len(hashes) - 1 else ""))
    return out


def chunk():
    r = rng.random()
    if r < 0.6:
        return req_block()
    if r < 0.75:
        return ["# " + rng.choice(["via foo", "a note", "coding standards", "x"])]
    if r < 0.85:
        return [rng.choice(OPTIONS)]
    return [""]


def mutate(text):
    for _ in range(rng.choice([0, 0, 1, 1, 2, 3])):
        pos = rng.randrange(len(text) + 1)
        kind = rng.random()
        if kind < 0.45:
            text = text[:pos] + rng.choice(TOKENS) + text[pos:]
        elif kind < 0.65 and text:
            pos = min(pos, len(text) - 1)
            text = text[:pos] + text[pos + 1:]
        elif kind < 0.85 and text:
            pos = min(pos, len(text) - 1)
            text = text[:pos] + rng.choice(TOKENS) + text[pos + 1:]
        else:
            text = text.replace(" ", "\t", 1) if rng.random() < 0.5 else text.replace(" \\", "\\", 1)
    return text


def generate():
    lines = []
    for _ in range(rng.randint(1, 5)):
        lines.extend(chunk())
    text = "\n".join(lines) + rng.choice(["\n", "\n", ""])
    text = mutate(text)
    if rng.random() < 0.2:
        text = text.replace("\n", "\r\n")
    if rng.random() < 0.05:
        text = "﻿" + text
    return text


def norm(name):
    return scope["norm"](name)


def helper_names(path):
    try:
        required, optional = scope["wanted"](path)
    except SystemExit as e:
        if e.code != 3:
            return "crash", "the helper exited %r" % (e.code,)
        return "refused", None
    except Exception as e:
        return "crash", "the helper raised %s: %s" % (type(e).__name__, e)
    return "accepted", set(required) | set(optional)


def pip_view(path, session):
    """Returns (ok, entries): entries are (normalised name or None for an editable, has hashes); ok is False when pip rejects the file."""
    entries = []
    try:
        for parsed in parse_requirements(path, session=session):
            name = None
            if not parsed.is_editable:
                try:
                    name = norm(Requirement(parsed.requirement).name)
                except Exception:
                    return False, []
            hashes = (parsed.options or {}).get("hashes") or {}
            entries.append((name, bool(hashes)))
    except (Exception, SystemExit):
        return False, []
    return True, entries


os.chdir(workdir)
sys.stderr = open(os.devnull, "w")
session = PipSession()
counts = {"accepted": 0, "refused": 0, "pip_error": 0, "pip_requirements": 0}
problems = []
start = time.time()
for n in range(count):
    text = generate()
    path = os.path.join(workdir, "requirements.txt")
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))
    verdict, names = helper_names(path)
    if verdict == "crash":
        problems.append((text, names))
        continue
    if verdict == "refused":
        counts["refused"] += 1
        continue
    counts["accepted"] += 1
    ok, entries = pip_view(path, session)
    if not ok:
        counts["pip_error"] += 1
        continue
    counts["pip_requirements"] += len(entries)
    for name, hashed in entries:
        if name is None or name not in names:
            problems.append((text, "pip sees %r, which the helper does not list (helper lists %s)" % (name, sorted(names))))
            break
        if not hashed:
            problems.append((text, "pip sees %s without hashes" % name))
            break
elapsed = time.time() - start
print("lock-parser-fuzz: pip %s, %d files, %d accepted by the helper, %d refused, %d that pip rejects, %d requirements checked, %d disagreements, %.1fs" % (pip_version, count, counts["accepted"], counts["refused"], counts["pip_error"], counts["pip_requirements"], len(problems), elapsed))
for text, why in problems[:5]:
    print("DISAGREE: %s\n  file: %r" % (why, text))
if problems:
    sys.exit(1)
if counts["accepted"] < count // 20 or counts["pip_requirements"] < count // 10:
    print("FAIL: too few accepted files or requirements, so the run proves little")
    sys.exit(1)
PY

OUT=$(cd "$T" && python3 -I "$T/fuzz.py" "$HELPER" "$COUNT" "$T" 2>&1)
EC=$?
printf '%s\n' "$OUT"
if [ "$EC" -eq 77 ]; then
  if [ -n "${CI:-}" ]; then
    echo "seeded-lock-parser-fuzz.test: pip's parser is missing and CI is set, so this cannot pass"
    exit 1
  fi
  echo "seeded-lock-parser-fuzz.test: SKIP (pip's parser is not importable here)"
  exit 0
fi
if [ "$EC" -eq 0 ]; then
  echo "seeded-lock-parser-fuzz.test: 1 passed, 0 failed"
  exit 0
fi
echo "seeded-lock-parser-fuzz.test: 0 passed, 1 failed"
exit 1

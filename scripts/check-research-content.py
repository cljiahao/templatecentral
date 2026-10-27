#!/usr/bin/env python3
"""Content guard for the ecosystem-refresh research file.

The file is web-derived text that later agent runs read as instructions, so it must not
carry text a reviewer cannot see. Raw HTML tags are rejected outside code spans. Exit codes: 0 = clean, 1 = hidden text or markup found,
anything else = the guard itself failed (the caller must treat that as a failure).
"""
import re
import sys

INVISIBLE = re.compile(
    "[­؜᠎​-‏‪-‮⁠-⁯﻿\U000e0000-\U000e007f]"
)
MARKUP = re.compile(
    r"<!--|<[A-Za-z]|javascript:|^[ \t]{0,3}\[[^\]\n]*\]:[ \t]*#",
    re.IGNORECASE | re.MULTILINE,
)
# Code spans render as visible literal text, so tags inside them hide nothing.
CODE = re.compile(r"```.*?```|`[^`\n]*`", re.DOTALL)


def main(path: str) -> int:
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        print("not valid UTF-8", file=sys.stderr)
        return 1
    if INVISIBLE.search(text):
        print("invisible or bidirectional control character found", file=sys.stderr)
        return 1
    match = MARKUP.search(CODE.sub("", text))
    if match:
        print(f"hidden-text markup found: {match.group(0)!r}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: check-research-content.py <file>", file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1]))
    except Exception as exc:  # an uncaught traceback would exit 1, which reads as "hidden text found"
        print(f"guard error: {exc}", file=sys.stderr)
        sys.exit(2)

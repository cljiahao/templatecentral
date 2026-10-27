#!/usr/bin/env python3
"""Content guard for the ecosystem-refresh research file.

The file is web-derived text that later agent runs read as instructions, so it must not
carry text a reviewer cannot see. The guard denies by category instead of listing known
tricks: any character that does not render as visible text, any tag-like text and any
markdown link-reference definition fails, even inside code spans.

Exit codes: 0 = clean, 1 = hidden text or markup found, anything else = the guard itself
failed (the caller must treat that as a failure).
"""
import re
import sys
import unicodedata

# Cc controls (newline and tab are allowed; a carriage return only inside CRLF), Cf format
# characters, Co private use, Cn unassigned, Zl/Zp line and paragraph separators.
DENIED_CATEGORIES = {"Cc", "Cf", "Co", "Cn", "Zl", "Zp"}
# Characters in other categories that render blank or change how their neighbours render.
DENIED_CHARS = {0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x2800, 0x3164, 0xFFA0}
DENIED_RANGES = (
    (0x180B, 0x180F),    # Mongolian free variation selectors and vowel separator
    (0xFE00, 0xFE0F),    # variation selectors
    (0xFFF9, 0xFFFB),    # interlinear annotation
    (0xE0100, 0xE01EF),  # variation selectors supplement
)
# A `<` followed by a letter, `/`, `!` or `?` (tags, comments, doctype, CDATA, processing
# instructions), any markdown link-reference definition (`[x]: ...` renders as nothing) and
# `javascript:` URLs.
MARKUP = re.compile(r"<[A-Za-z/!?]|^[ \t]{0,3}\[[^\]\n]*\]:|javascript:", re.IGNORECASE | re.MULTILINE)


def bad_character(text: str):
    """Return the first code point that is not visible text, or None."""
    for i, ch in enumerate(text):
        if ch == "\n" or ch == "\t" or (ch == "\r" and text[i + 1 : i + 2] == "\n"):
            continue
        cp = ord(ch)
        if (
            unicodedata.category(ch) in DENIED_CATEGORIES
            or cp in DENIED_CHARS
            or any(lo <= cp <= hi for lo, hi in DENIED_RANGES)
        ):
            return cp
    return None


def main(path: str) -> int:
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        print("not valid UTF-8", file=sys.stderr)
        return 1
    cp = bad_character(text)
    if cp is not None:
        print(f"character U+{cp:04X} is not visible text", file=sys.stderr)
        return 1
    match = MARKUP.search(text)
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

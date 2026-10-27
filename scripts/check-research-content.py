#!/usr/bin/env python3
"""Content guard for the ecosystem-refresh research file.

The file is web-derived text that later agent runs read as instructions, so it must not
carry text a reviewer cannot see. The research cache is plain prose and bullet lists, so
the guard bans whole constructs instead of chasing syntax variants: links, images,
reference definitions, tags, fences and indented code all fail, and so does any character
that does not render as visible text. It does not judge plain-text instructions; human PR
review does.

Exit codes: 0 = clean, 1 = hidden text or markup found, anything else = the guard itself
failed (the caller must treat that as a failure).
"""
import re
import sys
import unicodedata

MAX_LINE = 1500  # the longest line in the cache is 1333 characters

# Cc controls, Cf format characters, Co private use, Zl/Zp separators. Unassigned (Cn) is not
# denied: it depends on the interpreter's Unicode table and would reject newly added emoji.
DENIED_CATEGORIES = {"Cc", "Cf", "Co", "Zl", "Zp"}
# Characters in other categories that render blank or change how their neighbours render.
DENIED_CHARS = {0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x2800, 0x3164, 0xFFA0, 0xFFFC}
DENIED_RANGES = (
    (0x180B, 0x180F),    # Mongolian free variation selectors and vowel separator
    (0xFE00, 0xFE0D),    # variation selectors (FE0E/FE0F are handled separately)
    (0xFDD0, 0xFDEF),    # noncharacters
    (0xFFF9, 0xFFFB),    # interlinear annotation
    (0x2065, 0x2065),    # unassigned, default-ignorable (invisible)
    (0xFFF0, 0xFFF8),    # unassigned, default-ignorable (invisible)
    (0xE0000, 0xE0FFF),  # tag characters, variation selectors supplement and the unassigned rest of the block
)
# `<` followed by a letter, `/`, `!` or `?` (tags, comments, doctype, CDATA, processing
# instructions); `](` (inline link or image); `]:` (a reference definition, nested or split
# over lines); `![` (image); a fence line; 4+ leading spaces or a tab (indented code).
BANNED = re.compile(r"<[A-Za-z/!?]|\]\(|\]:|!\[|^[ \t]*(```|~~~)|^( {4,}|\t)", re.MULTILINE)


def bad_character(text: str):
    """Return the first code point that is not visible text, or None."""
    marks = 0
    for i, ch in enumerate(text):
        cp = ord(ch)
        cat = unicodedata.category(ch)
        marks = marks + 1 if cat == "Mn" else 0
        if marks >= 3:
            return cp
        if ch == "\n" or ch == "\t":
            continue  # a tab is only rejected as leading whitespace, by BANNED
        if cp in (0xFE0E, 0xFE0F):
            prev = text[i - 1] if i else ""
            if prev and (unicodedata.category(prev) in ("So", "Sk") or prev in "#*0123456789"):
                continue
            return cp
        if ch == " ":
            continue
        if (
            cat in DENIED_CATEGORIES
            or cat == "Zs"
            or cp in DENIED_CHARS
            or (cp & 0xFFFE) == 0xFFFE
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
    match = BANNED.search(text)
    if match:
        print(f"banned construct found: {match.group(0)!r}", file=sys.stderr)
        return 1
    if any(len(line) > MAX_LINE for line in text.split("\n")):
        print(f"line longer than {MAX_LINE} characters", file=sys.stderr)
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

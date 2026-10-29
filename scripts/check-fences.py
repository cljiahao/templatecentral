#!/usr/bin/env python3
"""Snapshot and check the copy-verbatim code fences of skills/add, skills/migrate and skills/standards.

A fence is copy-verbatim unless its language tag is bash, sh, shell, zsh or console. Each one is keyed by
file, nearest heading and its index among the fences under that heading (a heading text that repeats in
a file shares one counter). The hash is the sha256 of the fence body: its lines exactly as written
(an indented fence keeps its indentation), each ended by a newline. That is the byte content a real
file must hold to replace the fence.

Layout, under <root>/tests/golden/fences/:
  <skill>.tsv   one row per fence: sha256 TAB file TAB heading TAB index TAB lang
  moved.tsv     one row per fence that now lives in a file: file TAB heading TAB index TAB template-path
                (the path is relative to <root>, starts with skills/ and has a template* directory
                in it; '#' starts a comment line)

Usage:
  check-fences.py [--root DIR]                    check the markdown against the snapshot
  check-fences.py [--root DIR] --from-templates   hash only the moved fences, from their files
  check-fences.py [--root DIR] --has-mappings     exit 0 when moved.tsv has a row, else 1
  check-fences.py [--root DIR] --snapshot         write <skill>.tsv from the markdown (initial capture;
                                                  refuses once moved.tsv has a row)

Check results, one line each, exit 1 if any:
  MISMATCH  a fence (or the file that replaced it) differs from the snapshot
  MISSING   a snapshot row has no fence in the markdown and no mapping
  EXTRA     a fence has no snapshot row (a new fence or a new file)
  DUPLICATE a mapped fence is still in the markdown
  BADMAP    a mapping row names no snapshot row, repeats one, points outside template* under
            skills/, or points at a missing file
  EMPTY     nothing was compared
Exit 0 ok, 1 differences, 2 usage or parse error.
"""
import hashlib
import os
import re
import sys

SKILLS = ("add", "migrate", "standards")
SHELL_TAGS = {"bash", "sh", "shell", "zsh", "console"}
OPEN = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([^\s`]*)")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
HEADER = "# sha256\tfile\theading\tindex\tlang"
MOVED_HEADER = "# file\theading\tindex\ttemplate-path"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def scan(path, rel):
    """Return [(key, sha, lang)] for the copy-verbatim fences of one markdown file."""
    out, counters = [], {}
    heading, fence, body = "(top)", None, []
    with open(path, encoding="utf-8", newline="") as fh:
        lines = fh.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for line in lines:
        line = line.rstrip("\r")
        if fence is None:
            m = OPEN.match(line)
            if m:
                fence, body = (m.group(2)[0], len(m.group(2)), (m.group(3) or "-").lower()), []
                continue
            h = HEADING.match(line)
            if h:
                heading = h.group(1).replace("\t", " ")
            continue
        char, length, lang = fence
        stripped = line.strip()
        if stripped and set(stripped) == {char} and len(stripped) >= length:
            if lang.split("{")[0] not in SHELL_TAGS:
                idx = counters.get(heading, 0)
                counters[heading] = idx + 1
                data = "".join(b + "\n" for b in body).encode("utf-8")
                out.append(((rel, heading, idx), sha(data), lang))
            fence = None
            continue
        body.append(line)
    if fence is not None:
        raise ValueError(f"{rel}: unterminated fence under heading {heading!r}")
    return out


def scan_skills(root):
    rows = []
    for skill in SKILLS:
        base = os.path.join(root, "skills", skill)
        for dirpath, dirs, files in os.walk(base):
            dirs.sort()
            for f in sorted(files):
                if f.endswith(".md"):
                    full = os.path.join(dirpath, f)
                    rows += scan(full, os.path.relpath(full, root).replace(os.sep, "/"))
    return rows


def read_rows(path, width):
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != width:
                raise ValueError(f"{path}:{n}: want {width} tab-separated columns, got {len(cols)}")
            rows.append(cols)
    return rows


def key_text(key):
    return f"{key[0]} :: {key[1]} :: {key[2]}"


def main(argv):
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    mode = "check"
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--root" and args:
            root = os.path.abspath(args.pop(0))
        elif a in ("--from-templates", "--has-mappings", "--snapshot"):
            mode = a[2:]
        else:
            print(f"check-fences: usage: check-fences.py [--root DIR] [--from-templates|--has-mappings|--snapshot] (got {a})", file=sys.stderr)
            return 2
    gdir = os.path.join(root, "tests", "golden", "fences")
    try:
        moved_rows = read_rows(os.path.join(gdir, "moved.tsv"), 4)
        if mode == "has-mappings":
            return 0 if moved_rows else 1
        found = scan_skills(root)
        if mode == "snapshot":
            if moved_rows:
                print("check-fences: moved.tsv has rows; a snapshot taken now would drop the moved fences. Edit the rows by hand.", file=sys.stderr)
                return 2
            if not found:
                print("check-fences: no fences found; nothing to snapshot", file=sys.stderr)
                return 1
            os.makedirs(gdir, exist_ok=True)
            for skill in SKILLS:
                mine = [r for r in found if r[0][0].startswith(f"skills/{skill}/")]
                with open(os.path.join(gdir, f"{skill}.tsv"), "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(HEADER + "\n")
                    for (f, h, i), digest, lang in sorted(mine, key=lambda r: r[0]):
                        fh.write(f"{digest}\t{f}\t{h}\t{i}\t{lang}\n")
            print(f"check-fences: wrote {len(found)} fence rows")
            return 0
        snap = {}
        for skill in SKILLS:
            for digest, f, h, i, lang in read_rows(os.path.join(gdir, f"{skill}.tsv"), 5):
                key = (f, h, int(i))
                if key in snap:
                    print(f"BADMAP duplicate snapshot row {key_text(key)}")
                    return 1
                snap[key] = digest
    except (OSError, ValueError) as e:
        print(f"check-fences: {e}", file=sys.stderr)
        return 2
    if not snap:
        print("EMPTY the snapshot has no rows")
        return 1

    bad = 0
    mapped = {}
    for f, h, i, tpl in moved_rows:
        key = (f, h, int(i))
        parts = tpl.split("/")
        full = os.path.join(root, tpl)
        if key not in snap:
            print(f"BADMAP {key_text(key)} is not in the snapshot")
        elif key in mapped:
            print(f"BADMAP {key_text(key)} is mapped twice")
        elif parts[0] != "skills" or ".." in parts or not any(p.startswith("template") for p in parts[1:-1]):
            print(f"BADMAP {key_text(key)} -> {tpl} is not under a template* directory of skills/")
        elif not os.path.isfile(full) or os.path.islink(full):
            print(f"BADMAP {key_text(key)} -> {tpl} is not a regular file")
        else:
            mapped[key] = full
            continue
        bad = 1

    compared = 0
    for key, want in sorted(snap.items()):
        if key in mapped:
            compared += 1
            with open(mapped[key], "rb") as fh:
                if sha(fh.read()) != want:
                    print(f"MISMATCH {key_text(key)} -> {os.path.relpath(mapped[key], root)}")
                    bad = 1
    if mode == "from-templates":
        if not mapped and not bad:
            print("EMPTY no fence is mapped to a template file")
            bad = 1
        return 1 if bad else 0

    live = {r[0]: r[1] for r in found}
    if not live:
        print("EMPTY no fence was found in skills/add, skills/migrate or skills/standards")
        return 1
    for key, want in sorted(snap.items()):
        if key in mapped:
            if key in live:
                print(f"DUPLICATE {key_text(key)}")
                bad = 1
            continue
        compared += 1
        if key not in live:
            print(f"MISSING {key_text(key)}")
            bad = 1
        elif live[key] != want:
            print(f"MISMATCH {key_text(key)}")
            bad = 1
    for key in sorted(set(live) - set(snap)):
        print(f"EXTRA {key_text(key)}")
        bad = 1
    if compared == 0 and not bad:
        print("EMPTY nothing was compared")
        bad = 1
    if not bad:
        print(f"check-fences: {len(snap)} fences OK ({len(mapped)} in template files)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

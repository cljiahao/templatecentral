#!/usr/bin/env python3
"""Snapshot and check the copy-verbatim code fences of skills/add, skills/migrate and skills/standards.

A fence is copy-verbatim unless its language tag (the first word of the info string, cut at '{') is
bash, sh, shell, zsh or console. An untagged fence has the lang "-". Each fence is keyed by file,
nearest heading and its index among the fences under that heading (a heading text that repeats in a
file shares one counter). The hash is the sha256 of the fence body: its lines exactly as written,
each ended by a newline. A line keeps its indentation and a carriage return, so an LF-to-CRLF or an
indentation change fails, and a file that replaces the fence must end in a newline (a body with no
final newline does not match).

A fence opens at a line of 3 or more backticks or tildes indented by at most 3 spaces, or indented
by 0 to 3 spaces past the content column of the list item above it. A backtick opener whose info string holds a
backtick is not an opener. A fence closes at a line of the same character, at least as long, with
nothing else on it.

Layout, under <root>/tests/golden/fences/:
  <skill>.tsv      one row per fence: sha256 TAB file TAB heading TAB index TAB lang
                   Written once by --snapshot. A slice that moves fences into files never edits it.
  moved.d/*.tsv    one file per slice, read in sorted order; one row per fence that now lives in a file:
                   file TAB heading TAB index TAB template-path [TAB indent=N]
                   file, heading and index are the fence's snapshot row. The path is relative to <root>,
                   starts with skills/ and has a template* directory in it; neither the file nor a
                   directory above it may be a symlink. indent=N means the markdown fence is indented
                   by N spaces: N spaces are added to every non-empty line of the file before hashing
                   (a blank line of the fence must be empty: a line of only spaces inside an indented fence does not
                   round-trip and fails as MISMATCH). '#' starts a comment line.

Moving a fence leaves the index of its later siblings unchanged in the snapshot. The check drops the
mapped rows, then pairs the remaining rows of each heading with the live fences of that heading in
order, so the snapshot keeps its keys.

Usage:
  check-fences.py [--root DIR]                    check the markdown against the snapshot
  check-fences.py [--root DIR] --from-templates   hash only the mapped fences, from their files
  check-fences.py [--root DIR] --has-mappings     exit 0 when moved.d holds a row, 1 when it holds none, 2 on an error
  check-fences.py [--root DIR] --snapshot         write <skill>.tsv from the markdown (initial capture;
                                                  refuses once moved.d holds a row)

Check results, one line each, exit 1 if any:
  MISMATCH  a fence (or the file that replaced it) differs from the snapshot
  MISSING   a snapshot row has no fence in the markdown and no mapping
  EXTRA     a fence has no snapshot row (a new fence or a new file)
  DUPLICATE a mapped fence is still in the markdown
  BADMAP    a mapping row names no snapshot row, repeats one (in any file), points outside template*
            under skills/, goes through a symlink, or points at a missing file
  EMPTY     nothing was compared, or no copy-verbatim fence is left in the markdown and none is mapped
Exit 0 ok, 1 differences, 2 usage or parse error.
"""
import glob
import hashlib
import os
import re
import sys

SKILLS = ("add", "migrate", "standards")
SHELL_TAGS = {"bash", "sh", "shell", "zsh", "console"}
OPEN = re.compile(r"^( *)(`{3,}|~{3,})(.*)$")
LIST_ITEM = re.compile(r"^( *)([-*+]|\d{1,9}[.)])( +)\S")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
HEADER = "# sha256\tfile\theading\tindex\tlang"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def body_bytes(lines):
    return "".join(b + "\n" for b in lines).encode("utf-8")


def scan(path, rel):
    """Return [(key, sha, lang)] for the copy-verbatim fences of one markdown file."""
    out, counters = [], {}
    heading, fence, body, list_col = "(top)", None, [], None
    with open(path, encoding="utf-8", newline="") as fh:
        lines = fh.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for raw in lines:
        line = raw.rstrip("\r")
        if fence is None:
            m = OPEN.match(line)
            if m and not (m.group(2)[0] == "`" and "`" in m.group(3)):
                indent = len(m.group(1))
                if indent <= 3 or (list_col is not None and list_col <= indent <= list_col + 3):
                    info = m.group(3).split()
                    fence, body = (m.group(2)[0], len(m.group(2)), (info[0] if info else "-").lower()), []
                    continue
            h = HEADING.match(line)
            if h:
                heading, list_col = h.group(1).replace("\t", " "), None
                continue
            li = LIST_ITEM.match(line)
            if li:
                list_col = len(li.group(1)) + len(li.group(2)) + len(li.group(3))
            elif line.strip() and not line.startswith(" "):
                list_col = None
            continue
        char, length, lang = fence
        stripped = line.strip()
        if stripped and set(stripped) == {char} and len(stripped) >= length:
            if lang.split("{")[0] not in SHELL_TAGS:
                idx = counters.get(heading, 0)
                counters[heading] = idx + 1
                out.append(((rel, heading, idx), sha(body_bytes(body)), lang))
            fence = None
            continue
        body.append(raw)
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


def read_rows(path, widths):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) not in widths:
                raise ValueError(f"{path}:{n}: want {' or '.join(map(str, widths))} tab-separated columns, got {len(cols)}")
            rows.append(cols)
    return rows


def read_moved(gdir):
    """Return [(source file name, file, heading, index, template path, indent)] from moved.d/*.tsv."""
    rows = []
    for path in sorted(glob.glob(os.path.join(gdir, "moved.d", "*.tsv"))):
        for cols in read_rows(path, (4, 5)):
            indent = 0
            if len(cols) == 5:
                m = re.fullmatch(r"indent=(\d{1,2})", cols[4])
                if not m:
                    raise ValueError(f"{path}: fifth column must be indent=N, got {cols[4]!r}")
                indent = int(m.group(1))
            if not cols[2].isdigit():
                raise ValueError(f"{path}: index must be a number, got {cols[2]!r}")
            rows.append((os.path.basename(path), cols[0], cols[1], int(cols[2]), cols[3], indent))
    return rows


def key_text(key):
    return f"{key[0]} :: {key[1]} :: {key[2]}"


def symlink_in_chain(root, rel):
    """True when rel, or a directory above it under root, is a symlink."""
    parts = rel.split("/")
    return any(os.path.islink(os.path.join(root, *parts[:n])) for n in range(1, len(parts) + 1))


def reindent(data, indent):
    if not indent:
        return data
    pad = b" " * indent
    return b"".join((pad + ln if ln.strip(b"\r\n") else ln) for ln in data.splitlines(keepends=True))


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
        moved_rows = read_moved(gdir)
        if mode == "has-mappings":
            return 0 if moved_rows else 1
        found = scan_skills(root)
        if mode == "snapshot":
            if moved_rows:
                print("check-fences: moved.d has rows; a snapshot taken now would drop the moved fences.", file=sys.stderr)
                return 2
            if not found:
                print("check-fences: no fences found; nothing to snapshot", file=sys.stderr)
                return 1
            os.makedirs(os.path.join(gdir, "moved.d"), exist_ok=True)
            for skill in SKILLS:
                mine = [r for r in found if r[0][0].startswith(f"skills/{skill}/")]
                with open(os.path.join(gdir, f"{skill}.tsv"), "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(HEADER + "\n")
                    for (f, h, i), digest, lang in sorted(mine, key=lambda r: r[0]):
                        fh.write(f"{digest}\t{f}\t{h}\t{i}\t{lang}\n")
            print(f"check-fences: wrote {len(found)} fence rows")
            return 0
        snap, langs = {}, {}
        for skill in SKILLS:
            path = os.path.join(gdir, f"{skill}.tsv")
            if not os.path.isfile(path):
                continue
            for digest, f, h, i, lang in read_rows(path, (5,)):
                key = (f, h, int(i))
                if key in snap:
                    print(f"BADMAP duplicate snapshot row {key_text(key)}")
                    return 1
                snap[key], langs[key] = digest, lang
    except (OSError, ValueError) as e:
        print(f"check-fences: {e}", file=sys.stderr)
        return 2
    if not snap:
        print("EMPTY the snapshot has no rows")
        return 1

    bad = 0
    mapped = {}
    for src, f, h, i, tpl, indent in moved_rows:
        key = (f, h, i)
        parts = tpl.split("/")
        full = os.path.join(root, tpl)
        if key not in snap:
            print(f"BADMAP {key_text(key)} is not in the snapshot ({src})")
        elif key in mapped:
            print(f"BADMAP {key_text(key)} is mapped twice ({src} and {mapped[key][2]})")
        elif parts[0] != "skills" or ".." in parts or "" in parts or not any(p.startswith("template") for p in parts[1:-1]):
            print(f"BADMAP {key_text(key)} -> {tpl} is not under a template* directory of skills/ ({src})")
        elif symlink_in_chain(root, tpl):
            print(f"BADMAP {key_text(key)} -> {tpl} goes through a symlink ({src})")
        elif not os.path.isfile(full):
            print(f"BADMAP {key_text(key)} -> {tpl} is not a regular file ({src})")
        else:
            mapped[key] = (full, indent, src)
            continue
        bad = 1

    compared = 0
    for key, want in sorted(snap.items()):
        if key in mapped:
            compared += 1
            full, indent, _ = mapped[key]
            with open(full, "rb") as fh:
                if sha(reindent(fh.read(), indent)) != want:
                    print(f"MISMATCH {key_text(key)} -> {os.path.relpath(full, root)}")
                    bad = 1
    if mode == "from-templates":
        if not mapped and not bad:
            print("EMPTY no fence is mapped to a template file")
            bad = 1
        return 1 if bad else 0

    live = {}
    for key, digest, _lang in found:
        live.setdefault(key[:2], []).append(digest)
    if not live and not mapped:
        print("EMPTY no copy-verbatim fence was found in skills/add, skills/migrate or skills/standards, and none is mapped to a file")
        return 1
    groups = {}
    for key in snap:
        groups.setdefault(key[:2], []).append(key)
    for group in sorted(set(groups) | set(live)):
        rows = sorted(groups.get(group, []), key=lambda k: k[2])
        digests = list(live.get(group, []))
        kept = [k for k in rows if k not in mapped]
        # A mapped fence is still in the markdown only when the heading holds more fences than it has
        # unmapped rows; it is reported when removing one copy lines the rest up with the rows; otherwise the surplus is EXTRA.
        for k in rows:
            if k in mapped and len(digests) > len(kept) and snap[k] in digests:
                same = [i for i, d in enumerate(digests) if d == snap[k]]
                want = [snap[x] for x in kept]
                drop = next((i for i in same if (digests[:i] + digests[i + 1:])[:len(kept)] == want), None)
                if drop is not None:
                    del digests[drop]
                    print(f"DUPLICATE {key_text(k)}")
                    bad = 1
        for rank, k in enumerate(kept):
            compared += 1
            if rank >= len(digests):
                print(f"MISSING {key_text(k)}")
                bad = 1
            elif digests[rank] != snap[k]:
                print(f"MISMATCH {key_text(k)}")
                bad = 1
        for extra in range(len(kept), len(digests)):
            print(f"EXTRA {key_text((group[0], group[1], extra))}")
            bad = 1
    if compared == 0 and not bad:
        print("EMPTY nothing was compared")
        bad = 1
    if not bad:
        print(f"check-fences: {len(snap)} fences OK ({len(mapped)} in template files)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

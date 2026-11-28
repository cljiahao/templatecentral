#!/usr/bin/env python3
"""Scanner for check-exclude-reasons.sh: reads TOML and INI coverage and mutation settings without running anything."""
import configparser
import importlib
import os
import re
import sys

def norm_pat(x):
    """Reduce an entry to a plain pattern, as norm_pat in check-exclude-rules.sh does."""
    p = str(x)
    if p.startswith("!"):
        p = p[1:]
    if p.startswith("^"):
        p = p[1:]
    if p.endswith("$"):
        p = p[:-1]
    p = p.replace("\\.", ".").replace(".*", "*")
    while "//" in p or "/./" in p:
        p = p.replace("//", "/").replace("/./", "/")
    while p.startswith("./") or p.startswith("/"):
        p = p[2:] if p.startswith("./") else p[1:]
    if p == ".":
        p = ""
    return p[:-1] if p.endswith("/") else p


DEFAULTS = {norm_pat(d) for d in os.environ.get("TC_EXCLUDE_DEFAULTS", "").split("\n") if d} - {""}
REASON = re.compile(r"^reason:\s+\S+(\s+\S+){2,}\s*$")
PLACEHOLDERS = {w for w in os.environ.get("TC_REASON_PLACEHOLDERS", "").split("\n") if w}
DYNAMIC = "is not a plain list of strings; write it as a literal list of strings so each entry can carry a reason"


def emit(*fields):
    print("\t".join(re.sub(r"[\t\r\n]+", " ", str(f)) for f in fields))


class TomlError(Exception):
    def __init__(self, message, line):
        super().__init__(message)
        self.line = line


class Toml:
    """Line-aware TOML reader that keeps the line number of every value."""

    def __init__(self, text):
        self.s = text
        self.i = 0
        self.line = 1
        self.comments = {}

    def peek(self, n=1):
        return self.s[self.i : self.i + n]

    def adv(self, n=1):
        for _ in range(n):
            if self.i < len(self.s) and self.s[self.i] == "\n":
                self.line += 1
            self.i += 1

    def comment(self):
        """Skips a # comment and keeps its text when nothing else is on its line."""
        start = self.s.rfind("\n", 0, self.i) + 1
        end = self.s.find("\n", self.i)
        end = len(self.s) if end < 0 else end
        if self.s[start : self.i].strip() == "":
            self.comments[self.line] = self.s[self.i + 1 : end].strip()
        self.adv(end - self.i)

    def ws(self, newlines):
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in " \t\r" or (newlines and c == "\n"):
                self.adv()
            elif c == "#":
                self.comment()
            else:
                break

    def key_part(self):
        c = self.peek()
        if c in "\"'":
            return self.string()[1]
        start = self.i
        while self.i < len(self.s) and (self.s[self.i].isalnum() or self.s[self.i] in "_-"):
            self.adv()
        if start == self.i:
            raise TomlError("unreadable key", self.line)
        return self.s[start : self.i]

    def key_path(self):
        parts = [self.key_part()]
        while True:
            self.ws(False)
            if self.peek() != ".":
                return parts
            self.adv()
            self.ws(False)
            parts.append(self.key_part())

    def multiline_string(self, line):
        """Reads a triple quoted string; the opening quotes are still unread."""
        q3 = self.peek(3)
        self.adv(3)
        if self.peek() == "\n":
            self.adv()
        out = []
        while self.peek(3) != q3:
            if self.i >= len(self.s):
                raise TomlError("unterminated string", line)
            if q3 == '"""' and self.peek() == "\\":
                out.append(self.peek(2))
                self.adv(2)
                continue
            out.append(self.peek())
            self.adv()
        self.adv(3)
        return ("str", "".join(out), line)

    def single_line_string(self, q, line):
        """Reads a string with one quote character; the opening quote is still unread."""
        self.adv()
        out = []
        while self.peek() != q:
            if self.i >= len(self.s) or self.peek() == "\n":
                raise TomlError("unterminated string", line)
            if q == '"' and self.peek() == "\\":
                nxt = self.peek(2)[1:]
                mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "r": "\r"}
                out.append(mapping.get(nxt, "\\" + nxt))
                self.adv(2)
                continue
            out.append(self.peek())
            self.adv()
        self.adv()
        return ("str", "".join(out), line)

    def string(self):
        line = self.line
        if self.peek(3) in ('"""', "'''"):
            return self.multiline_string(line)
        return self.single_line_string(self.peek(), line)

    def items_until(self, close, read, message):
        """Reads comma separated items with the given reader up to the closing character, and consumes it."""
        while True:
            self.ws(True)
            if self.peek() == close:
                self.adv()
                return
            read()
            self.ws(True)
            if self.peek() == ",":
                self.adv()
            elif self.peek() != close:
                raise TomlError(message, self.line)

    def raw_value(self, line):
        """Reads an unquoted value up to a delimiter."""
        start = self.i
        while self.i < len(self.s) and self.s[self.i] not in ",]}\n#":
            self.adv()
        raw = self.s[start : self.i].strip()
        if not raw:
            raise TomlError("missing value", line)
        return ("raw", raw, line)

    def value(self):
        c = self.peek()
        line = self.line
        if c in "\"'":
            return self.string()
        if c == "[":
            self.adv()
            items = []
            self.items_until("]", lambda: items.append(self.value()), "unreadable array")
            return ("arr", items, line)
        if c == "{":
            self.adv()
            table = {}
            self.items_until("}", lambda: self.assign(table), "unreadable inline table")
            return ("tab", table, line)
        return self.raw_value(line)

    def assign(self, table):
        line = self.line
        path = self.key_path()
        self.ws(False)
        if self.peek() != "=":
            raise TomlError("expected =", self.line)
        self.adv()
        self.ws(False)
        node = self.value()
        cur = table
        for part in path[:-1]:
            nxt = cur.get(part)
            if nxt is None:
                nxt = (line, ("tab", {}, line))
                cur[part] = nxt
            if nxt[1][0] != "tab":
                raise TomlError("key redefined", line)
            cur = nxt[1][1]
        if path[-1] in cur:
            raise TomlError("the key %s is set twice, so a reason above one of them proves nothing; keep one" % ".".join(path), line)
        cur[path[-1]] = (line, node)

    def table_header(self):
        """Reads a [table] or [[array]] header and returns whether it is an array and its key path."""
        array = self.peek(2) == "[["
        width = 2 if array else 1
        self.adv(width)
        self.ws(False)
        path = self.key_path()
        self.ws(False)
        if self.peek(width) != ("]]" if array else "]"):
            raise TomlError("unreadable table header", self.line)
        self.adv(width)
        return array, path

    def open_table(self, root, array, path):
        """Walks or creates the tables on a header path and returns the table that holds the next keys."""
        cur = root
        for part in path:
            nxt = cur.get(part)
            if array and part == path[-1]:
                nxt = None
            if nxt is None:
                nxt = (self.line, ("tab", {}, self.line))
                cur[part] = nxt
            if nxt[1][0] == "arr":
                continue
            if nxt[1][0] != "tab":
                raise TomlError("table redefined", self.line)
            cur = nxt[1][1]
        return cur

    def parse(self):
        root = {}
        cur = root
        while True:
            self.ws(True)
            if self.i >= len(self.s):
                return root
            if self.peek() == "[":
                array, path = self.table_header()
                cur = self.open_table(root, array, path)
                continue
            self.assign(cur)
            self.ws(False)
            if self.i < len(self.s) and self.peek() not in "\n":
                raise TomlError("unexpected text after value", self.line)


def lookup(table, *path):
    cur = table
    leaf = None
    for part in path:
        if not isinstance(cur, dict) or part not in cur:
            return None
        leaf = cur[part]
        cur = leaf[1][1] if leaf[1][0] == "tab" else None
        if part != path[-1] and cur is None:
            return None
    return leaf


def as_strings(file, name, leaf):
    """Entries [(text, line)] of a string or list-of-strings leaf, or None after reporting."""
    line, node = leaf
    if node[0] == "str":
        return [(node[1], node[2])]
    if node[0] == "arr" and all(n[0] == "str" for n in node[1]):
        return [(n[1], n[2]) for n in node[1]]
    emit("X", file, line, "%s %s" % (name, DYNAMIC))
    return None


def has_reason(comments, line, entries=()):
    """A reason: at least 3 different words of 3+ letters; not a repeated single letter, not a path segment of the entries, no placeholder."""
    text = comments.get(line, "")
    if not REASON.match(text):
        return False
    words = [w.rstrip(".:!?").lower() for w in re.split(r"[\s,;\"`()]+", text[len("reason:"):]) if w.rstrip(".:!?")]
    if any(w in PLACEHOLDERS for w in words):
        return False
    segs = {part for e in entries for part in re.split(r"[/*{}, !]+", str(e).lower()) if part}
    good = set()
    for w in words:
        letters = re.sub(r"[^a-z]", "", w)
        if re.fullmatch(r"[a-z][a-z'-]*", w) and len(letters) >= 3 and len(set(letters)) > 1 and w not in segs:
            good.add(w)
    return len(good) >= 3


def emit_excludes(file, kind, comments, key_line, entries):
    own = [e for e in entries if norm_pat(e[0]) not in DEFAULTS]
    per_line = {}
    for _, line in own:
        per_line[line] = per_line.get(line, 0) + 1
    for text, line in entries:
        if norm_pat(text) in DEFAULTS:
            status = "default"
        elif per_line[line] > 1:
            status = "shared"
        elif has_reason(comments, line - 1, [text]) or (len(own) == 1 and has_reason(comments, key_line - 1, [own[0][0]])):
            status = "reason"
        else:
            status = "none"
        emit("E", file, line, kind, text, status)


def emit_include(file, comments, key_line, entries, kind="coverage-include"):
    if entries:
        texts = [e[0] for e in entries]
        emit("I", file, key_line, kind, ", ".join(texts), "reason" if has_reason(comments, key_line - 1, texts) else "none")


COVERAGE_KEYS = (
    ("omit", "coverage-exclude"),
    ("exclude_lines", "coverage-exclude"),
    ("exclude_also", "coverage-exclude"),
    ("include", "include"),
    ("source", "include"),
    ("source_pkgs", "include"),
)
MUTMUT_KEYS = (
    ("do_not_mutate", "mutation-exclude"),
    ("paths_to_exclude", "mutation-exclude"),
    ("paths_to_mutate", "mutation-include"),
    ("source_paths", "mutation-include"),
)


def handle(file, comments, section_label, key, kind, leaf, key_line):
    entries = as_strings(file, "%s %s" % (section_label, key), leaf)
    if entries is None:
        return None
    if kind == "include":
        emit_include(file, comments, key_line, entries)
    elif kind == "mutation-include":
        emit_include(file, comments, key_line, entries, "mutation-include")
    else:
        emit_excludes(file, kind, comments, key_line, entries)
    return entries


def threshold(file, leaf, key):
    line, node = leaf
    if node[0] == "raw" and re.fullmatch(r"\d+(\.\d+)?", node[1]):
        emit("T", file, line, key, node[1])


# The stdlib TOML reader, else the tomli package, else None; loaded by name so type checkers need no stub for either.
def load_toml_module():
    for name in ("tomllib", "tomli"):
        try:
            return importlib.import_module(name)
        except ImportError:
            continue
    return None


def read_reference(file, text):
    """Returns (readable, reference): reference is None when no TOML module exists, readable is False after a syntax error is reported."""
    tomllib = load_toml_module()
    if tomllib is None:
        return True, None
    try:
        return True, tomllib.loads(text)
    except tomllib.TOMLDecodeError as err:
        emit("X", file, 1, "toml has a syntax error: %s" % err)
        return False, None


def keep_entries(file, comments, label, key, kind, leaf, path, found):
    """Reports one setting and records its entries for the cross-check when it can be read."""
    entries = handle(file, comments, label, key, kind, leaf, leaf[0])
    if entries is not None:
        found.append((path, [e[0] for e in entries]))


def scan_coverage(file, comments, tool_tab, found):
    """Reports the coverage settings of the [tool.coverage] tables."""
    for section in ("run", "report"):
        for key, kind in COVERAGE_KEYS:
            leaf = lookup(tool_tab, "coverage", section, key)
            if leaf is not None:
                keep_entries(file, comments, "coverage %s.%s" % (section, key), key, kind, leaf, ("coverage", section, key), found)
        fail = lookup(tool_tab, "coverage", section, "fail_under")
        if fail is not None:
            threshold(file, fail, "fail_under")


def scan_mutmut(file, comments, tool_tab, found):
    """Reports the settings of the [tool.mutmut] table."""
    for key, kind in MUTMUT_KEYS:
        leaf = lookup(tool_tab, "mutmut", key)
        if leaf is not None:
            keep_entries(file, comments, "mutmut %s" % key, key, kind, leaf, ("mutmut", key), found)


def check_reference(file, reference, found):
    """Reports each setting the reference parser reads differently from the line-aware reader."""
    for path, values in found:
        cur = reference.get("tool", {})
        for part in path:
            cur = cur.get(part, {}) if isinstance(cur, dict) else {}
        expect = [cur] if isinstance(cur, str) else cur
        if expect != values:
            emit("X", file, 1, "%s read differently by the reference toml parser; the list must be a plain literal" % ".".join(path))


def emit_missing_reference(file):
    """Reports that no reference TOML parser is available."""
    emit(
        "X",
        file,
        1,
        "the cross-check of the TOML reader is missing: this Python is %d.%d and needs 3.11 or newer (tomllib), or the tomli package, to read coverage and mutation settings"
        % (sys.version_info[0], sys.version_info[1]),
    )


def scan_toml(file, text):
    parser = Toml(text)
    try:
        root = parser.parse()
    except TomlError as err:
        emit("X", file, err.line, "toml cannot be read: %s" % err)
        return
    readable, reference = read_reference(file, text)
    tool = lookup(root, "tool")
    if not readable or tool is None:
        return
    tool_tab = tool[1][1] if tool[1][0] == "tab" else {}
    found = []
    scan_coverage(file, parser.comments, tool_tab, found)
    scan_mutmut(file, parser.comments, tool_tab, found)
    if reference is not None:
        check_reference(file, reference, found)
    elif found or lookup(tool_tab, "coverage") is not None or lookup(tool_tab, "mutmut") is not None:
        emit_missing_reference(file)


class IniReader:
    """Collects comments and the wanted keys, with their entry lines, from an INI file one line at a time."""

    def __init__(self, file, sections):
        self.file = file
        self.sections = sections
        self.comments = {}
        self.wanted = {}
        self.section = None
        self.current = None

    def option(self, n, line):
        """Reads a key line and returns False when the line is not one."""
        m = re.match(r"^([^=:\s][^=:]*?)\s*[=:]\s*(.*)$", line)
        if not m:
            return False
        pair = (self.section, m.group(1).strip().lower())
        self.current = None
        if pair in self.sections:
            if pair in self.wanted:
                emit("X", self.file, n, "[%s] %s is set twice, so a reason above one of them proves nothing; keep one" % pair)
            self.current = {"key_line": n, "entries": []}
            self.wanted[pair] = self.current
            if m.group(2).strip():
                self.current["entries"].append((m.group(2).strip(), n))
        return True

    def feed(self, n, raw):
        line = raw.rstrip("\r")
        stripped = line.strip()
        if stripped[:1] in ("#", ";"):
            self.comments[n] = stripped[1:].strip()
            return
        if not stripped:
            return
        m = re.match(r"^\[([^\]]+)\]\s*$", line)
        if m:
            self.section, self.current = m.group(1), None
            return
        if not line[:1].isspace() and self.section is not None and self.option(n, line):
            return
        if self.current is not None and line[:1].isspace():
            self.current["entries"].append((stripped, n))


def emit_ini_keys(file, cp, reader):
    """Reports each wanted key of an INI file, or that configparser reads it differently."""
    for (sec, key), info in reader.wanted.items():
        kind = reader.sections[(sec, key)]
        entries = info["entries"]
        expect = [v.strip() for v in cp.get(sec, key).split("\n") if v.strip()]
        if expect != [e[0] for e in entries]:
            emit("X", file, info["key_line"], "[%s] %s read differently by configparser; write one entry per line" % (sec, key))
        elif kind == "include":
            emit_include(file, reader.comments, info["key_line"], entries)
        elif kind == "mutation-include":
            emit_include(file, reader.comments, info["key_line"], entries, "mutation-include")
        elif kind != "threshold":
            emit_excludes(file, kind, reader.comments, info["key_line"], entries)


def fail_under_line(text):
    """Returns the last line that sets fail_under, or 1."""
    at = 1
    for n, raw in enumerate(text.split("\n"), 1):
        if re.match(r"^\s*fail_under\s*[=:]", raw):
            at = n
    return at


def emit_ini_thresholds(file, cp, text, sections):
    """Reports a numeric fail_under in each coverage section."""
    for sec in {s for s, _ in sections}:
        if cp.has_section(sec) and cp.has_option(sec, "fail_under"):
            val = cp.get(sec, "fail_under").strip()
            if re.fullmatch(r"\d+(\.\d+)?", val):
                emit("T", file, fail_under_line(text), "fail_under", val)


def scan_ini(file, text, sections):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    try:
        cp.read_string(text)
    except configparser.Error as err:
        emit("X", file, 1, "ini cannot be read: %s" % str(err).splitlines()[0])
        return
    reader = IniReader(file, sections)
    for n, raw in enumerate(text.split("\n"), 1):
        reader.feed(n, raw)
    emit_ini_keys(file, cp, reader)
    emit_ini_thresholds(file, cp, text, sections)


def ini_sections(base):
    prefix = "coverage:" if base in ("setup.cfg", "tox.ini") else ""
    wanted = {}
    for section in ("run", "report"):
        for key, kind in COVERAGE_KEYS:
            wanted[(prefix + section, key)] = kind
    if base in ("setup.cfg", "tox.ini"):
        for key, kind in MUTMUT_KEYS:
            wanted[("mutmut", key)] = kind
    return wanted


def scan_jscpd(file, text):
    """jscpd reads .jscpd.json as strict JSON and drops the whole file on a comment, so no reason can sit in it; every ignore entry must be a framework default."""
    import json

    def pairs(items):
        keys = [k for k, _ in items]
        if len(keys) != len(set(keys)):
            raise ValueError("a key is set twice")
        return dict(items)

    doc = json.loads(text, object_pairs_hook=pairs)
    if not isinstance(doc, dict):
        raise ValueError("the top level is not an object")
    entries = doc.get("ignore", [])
    if not isinstance(entries, list) or not all(isinstance(e, str) for e in entries):
        emit("X", file, 1, "ignore %s" % DYNAMIC)
        return
    lines = text.split("\n")
    used = {}
    found = []
    for entry in entries:
        quoted = json.dumps(entry)
        seen = used.get(entry, 0)
        hits = [n for n, row in enumerate(lines, 1) for _ in range(row.count(quoted))]
        found.append((entry, hits[seen] if seen < len(hits) else 1))
        used[entry] = seen + 1
    emit_excludes(file, "cpd-ignore", {}, 1, found)


for path in sys.argv[1:]:
    name = os.path.basename(path)
    try:
        with open(path, encoding="utf-8") as handle_:
            body = handle_.read()
    except (OSError, UnicodeDecodeError) as err:
        emit("X", path, 1, "config could not be read: %s" % err)
        continue
    try:
        if name == ".jscpd.json":
            scan_jscpd(path, body)
        elif name.endswith(".toml"):
            scan_toml(path, body)
        else:
            scan_ini(path, body, ini_sections(name))
    except Exception as err:
        emit("X", path, 1, "config could not be read: %s" % err)

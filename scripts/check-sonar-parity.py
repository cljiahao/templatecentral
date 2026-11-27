"""Check scripts/sonar-parity.tsv against the seeded lint configs. Called by check-sonar-parity.sh.

Static only: no packages are installed and no config is executed. ESLint flat configs are read with a small
JavaScript reader; ruff settings from pyproject.toml; presets come from the snapshots in scripts/sonar-parity-presets/,
each tied to a pin in skills/scaffold/shared/versions.txt (regenerate with scripts/regen-sonar-parity-presets.py).
Fail closed: a config form this reader cannot resolve, a block it cannot prove covers all source files, a spread, call or
reference that is not a known preset, and a rule that needs type information in a stack that lints without it all fail.
"""
import os
import re
import sys
import types

LANGS = ("ts", "py")
STATUSES = ("covered", "partial", "not-covered")
TYPES = ("bug", "vulnerability", "code smell", "security hotspot", "quality gate")
COLS = 7
NO_PIN = ("sonar-rules",)
REGEN = "python3 -I scripts/regen-sonar-parity-presets.py --help"
SOURCE_EXTS = {"nextjs": ("ts", "tsx"), "vite-react": ("ts", "tsx"), "nestjs": ("ts",)}
TOOLING_ANYWHERE = ("node_modules", ".next", ".turbo", ".git", ".venv", "venv", "__pycache__")
TOOLING_DIRS = ("node_modules", "dist", "build", "out", "coverage", ".next", ".claude", ".turbo", ".git", ".venv", "venv",
                "__pycache__")
SEEDED_PY_HELPERS = ("scripts/check-comments.py", "scripts/check-exclude-reasons.py", "scripts/duplicate_tests_py.py", "scripts/py-env.py")
SEEDED_HELPERS = ("scripts/check-comments.mjs", "scripts/check-exclude-reasons.mjs", "scripts/duplicate-tests-ts.mjs")
# Config references the seeded files use today: (import source, dotted tail) -> (snapshot or None, rule prefixes it may touch).
# A None snapshot means the reference only adds rules under those prefixes (a plugin's own namespace); a mapped rule with one
# of those prefixes fails because the reference is not read.
PRESETS = {
    ("eslint-plugin-sonarjs", "configs.recommended"): ("sonarjs-recommended", ()),
    ("eslint-plugin-sonarjs", "configs.recommended.rules"): ("sonarjs-recommended", ()),
    ("typescript-eslint", "configs.recommended"): ("typescript-eslint-recommended", ()),
    ("typescript-eslint", "configs.recommendedTypeChecked"): ("typescript-eslint-recommended-type-checked", ()),
    ("@eslint/js", "configs.recommended"): ("eslint-recommended", ()),
    ("eslint-config-next/typescript", ""): ("next-typescript", ()),
    ("eslint-config-next/core-web-vitals", ""): ("next-core-web-vitals", ()),
    ("eslint-plugin-prettier/recommended", ""): ("eslint-config-prettier", ("prettier/",)),
    ("@eslint-community/eslint-plugin-eslint-comments/configs", "recommended"):
        (None, ("@eslint-community/eslint-comments/",)),
    ("eslint-plugin-no-unsanitized", "configs.recommended"): (None, ("no-unsanitized/",)),
    ("eslint-plugin-react-hooks", "configs.recommended.rules"): (None, ("react-hooks/",)),
}


class Unresolved(Exception):
    pass


# ---------------------------------------------------------------- snapshots

class Snap:
    def __init__(self):
        self.rows = {}
        self.pins = []
        self.extends = None
        self.touches = []


def load_snapshot(presets, name):
    snap = Snap()
    with open(os.path.join(presets, name + ".tsv"), encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            if line.startswith("#"):
                m = re.match(r"# (pin|extends|touches):\s*(.*)", line)
                if m and m.group(1) == "pin":
                    snap.pins.append(m.group(2).split())
                elif m and m.group(1) == "extends":
                    snap.extends = m.group(2).strip()
                elif m:
                    snap.touches = m.group(2).split()
                continue
            f = line.split("\t")
            snap.rows[f[0]] = tuple(f[1:])
    return snap


def read_pins(versions):
    pins = {}
    with open(versions, encoding="utf-8") as fh:
        for line in fh:
            f = line.split()
            if len(f) >= 3 and f[0] in ("npm", "pip"):
                pins[(f[0], f[1])] = f[2]
    return pins


def check_pins(presets, versions):
    errors = []
    try:
        pins = read_pins(versions)
    except OSError as exc:
        return ["cannot read %s: %s" % (versions, exc)]
    for fn in sorted(os.listdir(presets)):
        if not fn.endswith(".tsv"):
            continue
        name = fn[:-4]
        snap = load_snapshot(presets, name)
        if not snap.pins and name not in NO_PIN:
            errors.append("snapshot %s has no '# pin:' line; regenerate it (%s)" % (name, REGEN))
        for kind, pkg, spec in (p[:3] for p in snap.pins if len(p) >= 3):
            want = pins.get((kind, pkg))
            if want is None:
                errors.append("snapshot %s pins %s %s, which versions.txt does not list" % (name, kind, pkg))
            elif want != spec:
                errors.append("snapshot %s was generated for %s %s %s but versions.txt pins %s; regenerate it (%s)"
                              % (name, kind, pkg, spec, want, REGEN))
    return errors


# ---------------------------------------------------------------- JavaScript reader

TOKEN = re.compile(
    r"""\s+|//[^\n]*|/\*.*?\*/|(?P<str>'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")|(?P<num>\d+(?:\.\d+)?)"""
    r"""|(?P<id>[A-Za-z_$][\w$]*)|(?P<dots>\.\.\.)|(?P<p>[{}\[\](),:;.=?<>!+\-*/%&|^~@])""",
    re.S,
)
REGEX_PREV = "([{,:=!&|?;"


def tokenize(src, name):
    toks, lines = [], []
    pos = 0
    while pos < len(src):
        line = src.count("\n", 0, pos) + 1
        m = TOKEN.match(src, pos)
        if not m:
            what = "template literal" if src[pos] == "`" else "character %r" % src[pos]
            raise Unresolved("%s:%d: unsupported %s (template and regex literals are not read)" % (name, line, what))
        pos = m.end()
        tok = None
        if m.group("str") is not None:
            tok = ("str", m.group("str")[1:-1])
        elif m.group("num") is not None:
            tok = ("num", m.group("num"))
        elif m.group("id") is not None:
            tok = ("id", m.group("id"))
        elif m.group("dots") is not None:
            tok = ("p", "...")
        elif m.group("p") is not None:
            tok = ("p", m.group("p"))
        if tok is None:
            continue
        if tok == ("p", "/") and (not toks or (toks[-1][0] == "p" and toks[-1][1] in REGEX_PREV) or toks[-1] == ("id", "return")):
            raise Unresolved("%s:%d: unsupported regex literal (template and regex literals are not read)" % (name, line))
        toks.append(tok)
        lines.append(line)
    return toks, lines


class Parser:
    def __init__(self, toks, lines, name):
        self.t = toks
        self.lines = lines
        self.name = name
        self.i = 0
        self.imports = {}
        self.consts = {}
        self.default = None

    def fail(self, msg):
        idx = min(self.i, len(self.lines) - 1)
        raise Unresolved("%s:%d: %s" % (self.name, self.lines[idx] if self.lines else 0, msg))

    def peek(self, off=0):
        return self.t[self.i + off] if self.i + off < len(self.t) else ("eof", "")

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def expect(self, val):
        tok = self.take()
        if tok[1] != val or tok[0] not in ("p", "id"):
            self.fail("expected %s, found %s" % (val, tok[1]))

    def program(self):
        while self.peek()[0] != "eof":
            tok = self.peek()
            if tok == ("id", "import"):
                self.import_stmt()
            elif tok == ("id", "const"):
                self.take()
                name = self.take()[1]
                self.expect("=")
                self.consts[name] = self.expr()
                self.skip_semi()
            elif tok == ("id", "export"):
                self.take()
                self.expect("default")
                self.default = self.expr()
                self.skip_semi()
            else:
                self.fail("unsupported statement near %r" % tok[1])
        if self.default is None:
            self.fail("no default export")

    def skip_semi(self):
        if self.peek() == ("p", ";"):
            self.take()

    def import_stmt(self):
        self.take()
        names = []
        while self.peek()[0] != "str":
            tok = self.take()
            if tok[0] == "id" and tok[1] != "from":
                names.append(tok[1])
            if tok[0] == "eof":
                self.fail("bad import")
        src = self.take()[1]
        self.skip_semi()
        for n in names:
            self.imports[n] = src

    def expr(self):
        node = self.primary()
        while True:
            tok = self.peek()
            if tok == ("p", "."):
                self.take()
                node = ("member", node, self.take()[1])
            elif tok == ("p", "("):
                self.take()
                node = ("call", node, self.args(")"))
            elif tok == ("p", "["):
                self.take()
                idx = self.expr()
                self.expect("]")
                node = ("index", node, idx)
            elif tok[0] == "p" and tok[1] in "?:=<>!+-*/%&|^~":
                self.fail("operator %r in expression is not read" % tok[1])
            else:
                return node

    def args(self, close):
        out = []
        while self.peek() != ("p", close):
            if self.peek()[0] == "eof":
                self.fail("unterminated list")
            if self.peek() == ("p", "..."):
                self.take()
                out.append(("spread", self.expr()))
            else:
                out.append(self.expr())
            if self.peek() == ("p", ","):
                self.take()
        self.take()
        return out

    def primary(self):
        tok = self.take()
        if tok[0] == "str":
            return ("str", tok[1])
        if tok[0] == "num":
            return ("num", tok[1])
        if tok[0] == "id":
            return ("ref", tok[1])
        if tok == ("p", "["):
            return ("array", self.args("]"))
        if tok == ("p", "{"):
            return self.obj()
        self.fail("unexpected %r" % (tok[1],))
        return None

    def obj(self):
        members = []
        while self.peek() != ("p", "}"):
            if self.peek()[0] == "eof":
                self.fail("unterminated object")
            if self.peek() == ("p", "..."):
                self.take()
                members.append(("spread", self.expr()))
            else:
                ktok = self.take()
                if ktok[0] not in ("str", "id"):
                    self.fail("unsupported object key %r" % ktok[1])
                self.expect(":")
                members.append((ktok[1], self.expr()))
            if self.peek() == ("p", ","):
                self.take()
        self.take()
        return ("object", members)


# ---------------------------------------------------------------- globs

def expand_braces(pat):
    m = re.search(r"\{([^{}]*)\}", pat)
    if not m:
        return [pat]
    out = []
    for alt in m.group(1).split(","):
        out.extend(expand_braces(pat[:m.start()] + alt + pat[m.end():]))
    return out


def is_test_glob(pat, py=False):
    segs = pat.split("/")
    if ".." in segs:
        return False
    if any(s in ("test", "tests", "__tests__") for s in segs[:-1]):
        return True
    last = segs[-1]
    if re.search(r"\.(test|spec|e2e-spec)\.", last):
        return True
    return py and (last.startswith("test_") or last.endswith("_test.py") or last == "conftest.py")


def tooling_path(pat):
    """Build or tooling paths a global ignore may hide, and the exact names of the seeded gate helpers (guarded files nobody edits). Folders that can also be source folders (dist, build, out, coverage,
    .claude) count only when anchored at the project root: '**/out/**' also hides src/out/. Config files count at the root only."""
    if pat.startswith("!") or ".." in pat.split("/"):
        return False
    if pat in SEEDED_HELPERS:
        return True
    group = re.fullmatch(r"(scripts/)\{([\w.-]+(?:,[\w.-]+)+)\}(\.mjs)", pat)
    if group:
        return all(group.group(1) + name + group.group(3) in SEEDED_HELPERS for name in group.group(2).split(","))
    q = re.sub(r"^(\*\*/)+", "", pat)
    anywhere = pat != q and q.split("/")[0] in TOOLING_ANYWHERE
    return (anywhere or (pat == q and (pat.split("/")[0] in TOOLING_DIRS or pat == "next-env.d.ts"))
            or re.fullmatch(r"[\w.*-]*\.config(\.[\w-]+)?\.(m?[jt]s|cjs|cts)", pat) is not None)


def all_form_exts(pats):
    """Extensions a list of '**/*.ext' patterns covers, '*' for '**/*'; None when any pattern has another shape."""
    exts = set()
    for p in pats:
        m = re.fullmatch(r"\*\*/\*(?:\.([A-Za-z]+))?", p)
        if not m:
            return None
        exts.add(m.group(1) or "*")
    return exts


# ---------------------------------------------------------------- ESLint evaluation

def dotted(node):
    if node[0] == "ref":
        return [node[1]]
    if node[0] == "member":
        base = dotted(node[1])
        return base + [node[2]] if base else None
    return None


class Block:
    def __init__(self, rules, files, ignores, ta=None):
        self.rules = rules
        self.files = files
        self.ignores = ignores
        self.ta = ta  # True/False when the block sets parserOptions.projectService or project, else None


class Eval:
    def __init__(self, parser, presets):
        self.p = parser
        self.presets = presets
        self.cache = {}
        self.touches = set()
        self.global_ignores = []

    def snap_rules(self, name):
        if name not in self.cache:
            snap = load_snapshot(self.presets, name)
            rules = {}
            if snap.extends:
                rules.update(self.snap_rules(snap.extends)[0])
            rules.update((k, v[0]) for k, v in snap.rows.items())
            self.cache[name] = (rules, snap.touches)
        return self.cache[name]

    def lookup(self, path):
        """(rules, touches) of a known preset reference, or None."""
        if not path:
            return None
        entry = PRESETS.get((self.p.imports.get(path[0], ""), ".".join(path[1:])))
        if entry is None:
            return None
        rules, touches = ({}, []) if entry[0] is None else self.snap_rules(entry[0])
        return dict(rules), list(touches) + list(entry[1])

    def deref(self, node):
        seen = 0
        while node[0] == "ref" and node[1] in self.p.consts and seen < 20:
            node = self.p.consts[node[1]]
            seen += 1
        return node

    def known(self, node, where):
        path = dotted(self.deref(node))
        preset = self.lookup(path)
        if preset is None:
            raise Unresolved("%s refers to %s, which is not a known config preset" % (where, ".".join(path) if path else "an expression"))
        self.touches.update(preset[1])
        return preset[0]

    def blocks(self, node, out, files=None, ignores=None):
        node = self.deref(node)
        kind = node[0]
        if kind == "array":
            for el in node[1]:
                self.blocks(el[1] if el[0] == "spread" else el, out, files, ignores)
        elif kind == "call":
            path = dotted(node[1])
            if not (path and path[-1] == "config" and self.p.imports.get(path[0]) == "typescript-eslint"):
                raise Unresolved("call to %s in the config is not read" % (".".join(path) if path else "an expression"))
            for a in node[2]:
                self.blocks(a[1] if a[0] == "spread" else a, out, files, ignores)
        elif kind == "object":
            self.object_block(node, out, files, ignores)
        elif kind in ("ref", "member"):
            out.append(Block(self.known(node, "the config array"), files, ignores))
        else:
            raise Unresolved("unsupported element in the config array")

    def object_block(self, node, out, inherited_files, inherited_ignores):
        rules = {}
        files, ignores, ta = None, None, None
        # Object-literal order: a spread or a 'rules' key replaces everything gathered so far, as in JavaScript.
        for key, val in node[1]:
            if key == "spread":
                rules = self.known(val, "a block-level spread")
            elif key == "files":
                files = self.str_list(val, "files")
            elif key == "ignores":
                ignores = self.str_list(val, "ignores")
            elif key == "rules":
                rules = self.rules_obj(val)
            elif key == "languageOptions":
                try:
                    ta = self.parser_type_aware(val)
                except Unresolved as exc:
                    raise Unresolved("%s, in %s" % (exc, self.describe(node)))
        if ignores is not None and files is None and rules == {} and all(k in ("ignores", "name") for k, _ in node[1]):
            for pat in ignores:
                if not tooling_path(pat):
                    raise Unresolved("global ignores entry %r is not a build or tooling path" % pat)
            self.global_ignores.extend(ignores)
            return
        sub_files = files if files is not None else inherited_files
        sub_ignores = ignores if ignores is not None else inherited_ignores
        for key, val in node[1]:
            if key == "extends":
                self.blocks(val, out, sub_files, sub_ignores)
        out.append(Block(rules, sub_files, sub_ignores, ta))

    @staticmethod
    def describe(node):
        for key, val in node[1]:
            if key == "name" and val[0] == "str":
                return "the block named %r" % val[1]
        return "the block with keys %s" % ", ".join(k for k, _ in node[1] if k != "spread")

    def parser_type_aware(self, node):
        """True when languageOptions.parserOptions turns type information on, False when it sets and disables it, else None.
        Duplicate keys follow JavaScript: the last one wins (a later parserOptions replaces the earlier object whole)."""
        node = self.deref(node)
        if node[0] != "object":
            raise Unresolved("languageOptions is not an object literal")
        opts = None
        for key, val in node[1]:
            if key == "spread":
                raise Unresolved("a spread in languageOptions is not read")
            if key == "parserOptions":
                opts = self.deref(val)
                if opts[0] != "object":
                    raise Unresolved("parserOptions is not an object literal")
        if opts is None:
            return None
        got = {}
        for k, v in opts[1]:
            if k == "spread":
                raise Unresolved("a spread in parserOptions is not read")
            if k in ("projectService", "project"):
                got[k] = self.truthy(v, k)
        if not got:
            return None
        return any(got.values())

    def truthy(self, node, what):
        node = self.deref(node)
        if node == ("ref", "true") or node[0] == "object":
            return True
        if node in (("ref", "false"), ("ref", "null"), ("ref", "undefined")):
            return False
        if what == "project" and node[0] == "str":
            return node[1] != ""
        if what == "project" and node[0] == "array" and all(self.deref(e)[0] == "str" for e in node[1]):
            return any(self.deref(e)[1] != "" for e in node[1])
        raise Unresolved("parserOptions.%s is not a literal" % what)

    def str_list(self, node, what):
        node = self.deref(node)
        if node[0] != "array":
            raise Unresolved("%s is not an array literal" % what)
        out = []
        for el in node[1]:
            if el[0] != "str":
                raise Unresolved("%s holds a non-literal" % what)
            out.append(el[1])
        return out

    def rules_obj(self, node):
        node = self.deref(node)
        if node[0] != "object":
            raise Unresolved("rules is not an object literal")
        rules = {}
        for key, val in node[1]:
            if key == "spread":
                inner = self.deref(val)
                rules.update(self.rules_obj(inner) if inner[0] == "object" else self.known(val, "a spread in rules"))
            else:
                rules[key] = self.level(val)
        return rules

    def level(self, node):
        node = self.deref(node)
        if node[0] == "array":
            if not node[1]:
                raise Unresolved("empty rule array")
            node = self.deref(node[1][0])
        if node[0] == "str" and node[1] in ("error", "warn", "off"):
            return node[1]
        if node[0] == "num" and node[1] in ("0", "1", "2"):
            return {"0": "off", "1": "warn", "2": "error"}[node[1]]
        raise Unresolved("rule level is not a literal")


class Stack:
    def __init__(self, name, blocks, touches):
        self.name = name
        self.blocks = blocks
        self.touches = touches
        self.type_aware = False
        self.exts = SOURCE_EXTS[name]
        self.notes = []

    def scope(self, block, rule):
        """'all' when the block applies to every ordinary source file, 'test' when only to test files."""
        if block.ignores and not all(is_test_glob(p) for i in block.ignores for p in expand_braces(i)):
            raise Unresolved("a block with ignores %s sets %s; cannot prove the ignores leave source files alone" % (block.ignores, rule))
        if block.files is None:
            return "all"
        pats = [p for f in block.files for p in expand_braces(f)]
        if all(is_test_glob(p) for p in pats):
            return "test"
        exts = all_form_exts(pats)
        if exts is not None and ("*" in exts or all(e in exts for e in self.exts)):
            return "all"
        raise Unresolved("a block with files %s sets %s; cannot prove it covers all source files or only tests" % (block.files, rule))

    def last(self, pick, what, on_test=None):
        """Value from the last block that sets it and covers all source files. Walks back to front, so a block that covers
        everything hides earlier partial ones; a later block whose scope cannot be proven raises."""
        for block in reversed(self.blocks):
            got = pick(block)
            if got is None:
                continue
            if self.scope(block, what) == "test":
                if on_test:
                    on_test(got)
                continue
            return got
        return None

    def level(self, rule):
        for prefix in self.touches:
            if rule.startswith(prefix):
                raise Unresolved("%s is under %s, set by a config reference that is not read rule by rule" % (rule, prefix))
        return self.last(lambda b: b.rules.get(rule), rule,
                         lambda lvl: self.notes.append("%s: %s set to %s for test files only (not counted)" % (self.name, rule, lvl)))

    def resolve_type_aware(self):
        return bool(self.last(lambda b: b.ta, "parserOptions.projectService"))


def eslint_stack(name, path, rel, presets):
    with open(path, encoding="utf-8") as fh:
        toks, lines = tokenize(fh.read(), rel)
    parser = Parser(toks, lines, rel)
    parser.program()
    ev = Eval(parser, presets)
    out = []
    ev.blocks(parser.default, out)
    stack = Stack(name, out, ev.touches)
    stack.type_aware = stack.resolve_type_aware()
    return stack


# ---------------------------------------------------------------- ruff

class Bad:
    """A TOML value the scanner found but does not decode (multi-line string, unknown escape). Raises where it is read."""

    def __init__(self, why):
        self.why = why


class Inline(dict):
    """An inline table value: { key = value }."""


ESCAPES = {"b": "\b", "t": "\t", "n": "\n", "f": "\f", "r": "\r", '"': '"', "\\": "\\"}
BARE = re.compile(r"[A-Za-z0-9_-]+")
NUMBER = re.compile(r"[+-]?(?:0x[0-9a-fA-F_]+|inf|nan|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?)")


class TomlScan:
    """Strict reader for the TOML subset pyproject.toml uses. Accepts tables, [[array tables]], dotted headers and keys, bare,
    basic and literal keys, basic and literal strings (escapes b t n f r \\" \\\\ uXXXX UXXXXXXXX), integers, floats, booleans,
    arrays over several lines, inline tables, comments. Raises Unresolved on a duplicate key, a table defined twice (also by a
    dotted key), a bad key, an unknown value (dates, bare words) and a malformed line. Multi-line strings and unknown escapes
    become Bad values: they fail only where the ruff reader needs the value."""

    def __init__(self, text):
        self.s = text
        self.i = 0

    def fail(self, msg):
        raise Unresolved("pyproject.toml line %d: %s" % (self.s.count("\n", 0, self.i) + 1, msg))

    def peek(self, n=1):
        return self.s[self.i:self.i + n]

    def blank(self):
        while self.peek() in (" ", "\t"):
            self.i += 1

    def comment(self):
        if self.peek() == "#":
            while self.i < len(self.s) and self.s[self.i] != "\n":
                self.i += 1

    def eol(self):
        self.blank()
        self.comment()
        if self.i < len(self.s):
            if self.s[self.i] == "\r":
                self.i += 1
            if self.peek() != "\n":
                self.fail("unexpected text after a value")
            self.i += 1

    def skip_all(self):
        """Whitespace, newlines and comments between array elements (comments are read here, never inside a string)."""
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif c == "#":
                self.comment()
            else:
                return

    def string(self):
        q = self.s[self.i]
        if self.peek(3) == q * 3:
            self.i += 3
            while self.i < len(self.s):
                if q == '"' and self.s[self.i] == "\\":
                    self.i += 2
                elif self.peek(3) == q * 3:
                    self.i += 3
                    while self.peek() == q:
                        self.i += 1
                    return Bad("multi-line strings are not read")
                else:
                    self.i += 1
            self.fail("unterminated multi-line string")
        self.i += 1
        out, bad = [], None
        while True:
            if self.i >= len(self.s) or self.s[self.i] == "\n":
                self.fail("unterminated string")
            c = self.s[self.i]
            if c == q:
                self.i += 1
                return Bad(bad) if bad else "".join(out)
            if q == '"' and c == "\\":
                e = self.s[self.i + 1:self.i + 2]
                if e in ESCAPES:
                    out.append(ESCAPES[e])
                    self.i += 2
                elif e in ("u", "U"):
                    n = 4 if e == "u" else 8
                    hexa = self.s[self.i + 2:self.i + 2 + n]
                    if len(hexa) != n or not re.fullmatch(r"[0-9a-fA-F]+", hexa):
                        self.fail("bad unicode escape")
                    try:
                        out.append(chr(int(hexa, 16)))
                    except (ValueError, OverflowError):
                        self.fail("bad unicode escape")
                    self.i += 2 + n
                else:
                    bad = bad or "escape \\%s is not decoded" % e
                    self.i += 2
            else:
                out.append(c)
                self.i += 1

    def key_path(self):
        parts = []
        while True:
            self.blank()
            c = self.peek()
            if c in ('"', "'"):
                k = self.string()
                if isinstance(k, Bad):
                    self.fail("a quoted key with %s" % k.why)
            else:
                m = BARE.match(self.s, self.i)
                if not m:
                    self.fail("expected a key")
                k = m.group()
                self.i = m.end()
            parts.append(k)
            self.blank()
            if self.peek() != ".":
                return parts
            self.i += 1

    def value(self):
        self.blank()
        c = self.peek()
        if c in ('"', "'"):
            return self.string()
        if c == "[":
            self.i += 1
            out = []
            while True:
                self.skip_all()
                if self.peek() == "]":
                    self.i += 1
                    return out
                out.append(self.value())
                self.skip_all()
                if self.peek() == ",":
                    self.i += 1
                elif self.peek() != "]":
                    self.fail("expected , or ] in an array")
        if c == "{":
            self.i += 1
            tbl = Inline()
            self.blank()
            if self.peek() == "}":
                self.i += 1
                return tbl
            while True:
                path = self.key_path()
                self.blank()
                if self.peek() != "=":
                    self.fail("expected = in an inline table")
                self.i += 1
                put(tbl, path, self.value(), self)
                self.blank()
                if self.peek() == ",":
                    self.i += 1
                elif self.peek() == "}":
                    self.i += 1
                    return tbl
                else:
                    self.fail("expected , or } in an inline table")
        for word, val in (("true", True), ("false", False)):
            if self.peek(len(word)) == word and not re.match(r"[\w.-]", self.s[self.i + len(word):self.i + len(word) + 1] or " "):
                self.i += len(word)
                return val
        m = NUMBER.match(self.s, self.i)
        if m and not re.match(r"[\w.:-]", self.s[m.end():m.end() + 1] or " "):
            self.i = m.end()
            return m.group()
        self.fail("unsupported value (dates, bare words and the like are not read)")
        return None


def put(tbl, path, val, sc, dotted=None):
    for k in path[:-1]:
        nxt = tbl.get(k)
        if nxt is None:
            nxt = tbl[k] = {}
            if dotted is not None:
                dotted.add(id(nxt))
        elif isinstance(nxt, list) and nxt and isinstance(nxt[-1], dict):
            nxt = nxt[-1]
        elif not isinstance(nxt, dict) or isinstance(nxt, Inline):
            sc.fail("key %s is not a table" % k)
        tbl = nxt
    if path[-1] in tbl:
        sc.fail("duplicate key %s" % ".".join(path))
    tbl[path[-1]] = val
    return tbl


def toml_parse(text):
    sc = TomlScan(text)
    root = {}
    cur = root
    explicit, dotted = set(), set()
    while sc.i < len(sc.s):
        sc.blank()
        c = sc.peek()
        if c in ("\n", "\r", "#", ""):
            sc.eol()
            continue
        if c == "[":
            array = sc.peek(2) == "[["
            sc.i += 2 if array else 1
            path = sc.key_path()
            sc.blank()
            if sc.peek(2 if array else 1) != ("]]" if array else "]"):
                sc.fail("unterminated table header")
            sc.i += 2 if array else 1
            sc.eol()
            tbl = root
            for k in path[:-1]:
                nxt = tbl.setdefault(k, {})
                if isinstance(nxt, list) and nxt and isinstance(nxt[-1], dict):
                    nxt = nxt[-1]
                if not isinstance(nxt, dict) or isinstance(nxt, Inline):
                    sc.fail("table %s clashes with a value" % ".".join(path))
                tbl = nxt
            last = path[-1]
            if array:
                lst = tbl.setdefault(last, [])
                if not isinstance(lst, list):
                    sc.fail("table %s clashes with a value" % ".".join(path))
                cur = {}
                lst.append(cur)
            else:
                existing = tbl.get(last)
                if existing is not None and (id(existing) in dotted or id(existing) in explicit
                                             or not isinstance(existing, dict) or isinstance(existing, Inline)):
                    sc.fail("table [%s] is defined twice (a dotted key, an inline table or a repeated header)" % ".".join(path))
                cur = tbl[last] = existing if existing is not None else {}
                explicit.add(id(cur))
            continue
        path = sc.key_path()
        sc.blank()
        if sc.peek() != "=":
            sc.fail("expected = after a key")
        sc.i += 1
        put(cur, path, sc.value(), sc, dotted)
        sc.eol()
    return root


RUFF_LEGACY = ("select", "ignore", "extend-select", "extend-ignore", "per-file-ignores", "extend-per-file-ignores")


def ruff_walk(node, path):
    """Raise on a value under [tool.ruff] the scanner could not decode."""
    if isinstance(node, Bad):
        raise Unresolved("%s: %s" % (path, node.why))
    if isinstance(node, dict):
        for k, v in node.items():
            ruff_walk(v, path + "." + k)
    elif isinstance(node, list):
        for v in node:
            ruff_walk(v, path)


def str_items(val, what):
    if not isinstance(val, list) or not all(isinstance(x, str) for x in val):
        raise Unresolved("%s is not a list of strings" % what)
    return val


def flag(lint, top, key):
    """lint.<key> overrides the deprecated top-level <key>; the value must be a boolean literal."""
    for body in (lint, top):
        if key in body:
            if not isinstance(body[key], bool):
                raise Unresolved("%s is not a boolean literal" % key)
            return body[key]
    return False


def seeded_py_only(value):
    """True when a top-level extend-exclude lists only the exact seeded Python gate helpers (guarded files nobody edits)."""
    return isinstance(value, list) and all(isinstance(v, str) and v in SEEDED_PY_HELPERS for v in value)


def ruff_state(path):
    with open(path, encoding="utf-8") as fh:
        doc = toml_parse(fh.read())
    for fn in ("ruff.toml", ".ruff.toml"):
        if os.path.exists(os.path.join(os.path.dirname(path), fn)):
            raise Unresolved("%s beside pyproject.toml takes precedence and is not read" % fn)
    tool = doc.get("tool")
    top = tool.get("ruff") if isinstance(tool, dict) else None
    if top is not None and not isinstance(top, dict):
        raise Unresolved("[tool.ruff] is not a table")
    lint = (top or {}).get("lint")
    if not isinstance(lint, dict):
        raise Unresolved("no [tool.ruff.lint] table")
    if any(isinstance(t, Inline) for t in (tool, top, lint)):
        raise Unresolved("an inline table where [tool.ruff] or [tool.ruff.lint] is expected is not read")
    ruff_walk(top, "tool.ruff")
    if "extend" in top:
        raise Unresolved("extend in [tool.ruff] pulls in a config that is not read")
    for key in RUFF_LEGACY:
        if key in top:
            raise Unresolved("legacy top-level %s in [tool.ruff]; use [tool.ruff.lint]" % key)
    for key in ("per-file-ignores", "extend-per-file-ignores"):
        if isinstance(lint.get(key), Inline):
            raise Unresolved("inline %s is not read; use a [tool.ruff.lint.%s] table" % (key, key))
    for body in (top, lint):
        for key in ("exclude", "extend-exclude"):
            if key in body and not (body is top and key == "extend-exclude" and seeded_py_only(body[key])):
                raise Unresolved("%s is not read" % key)
    st = types.SimpleNamespace()
    st.select = str_items(lint.get("select", []), "select") + str_items(lint.get("extend-select", []), "extend-select")
    st.ignore = str_items(lint.get("ignore", []), "ignore") + str_items(lint.get("extend-ignore", []), "extend-ignore")
    st.preview = flag(lint, top, "preview")
    st.explicit_preview = flag(lint, top, "explicit-preview-rules")
    st.pfi = []
    for key in ("per-file-ignores", "extend-per-file-ignores"):
        tbl = lint.get(key, {})
        if not isinstance(tbl, dict):
            raise Unresolved("%s is not a table" % key)
        for pat, codes in tbl.items():
            st.pfi.append((pat, str_items(codes, "per-file-ignores entry %r" % pat)))
    if not st.select:
        raise Unresolved("no select list (ruff defaults are not assumed)")
    return st


def split_code(code):
    m = re.fullmatch(r"([A-Z]+)([0-9]*)", code)
    return m.groups() if m else None


def selector_matches(sel, code, linters):
    """ruff selector semantics: the longest linter prefix picks the linter; a selector without digits takes the whole linter
    ('S' is flake8-bandit only, never 'SIM'), digits match by prefix inside that linter. 'PL' is the one documented group (PLC/PLE/PLR/PLW); any other
    prefix that is not itself a linter ('PG', 'R') is rejected."""
    if sel == "ALL":
        return True
    parts = split_code(sel)
    group = parts is not None and parts == ("PL", "") and any(l.startswith("PL") for l in linters)
    if parts is None or not (parts[0] in linters or group):
        raise Unresolved("ruff selector %r is not a code or linter prefix in the ruff-rules snapshot" % sel)
    have = split_code(code)
    if parts[0] in linters:
        return have[0] == parts[0] and have[1].startswith(parts[1])
    return have[0].startswith("PL")


def ruff_linters(rules):
    return set(split_code(c)[0] for c in rules if split_code(c))


def check_selectors(st, linters):
    for sel in st.select + st.ignore + [c for _, codes in st.pfi for c in codes]:
        selector_matches(sel, "E401", linters)


def specificity(code, selectors, linters):
    best = None
    for s in selectors:
        if not selector_matches(s, code, linters):
            continue
        n = 0 if s == "ALL" else len(s)
        best = n if best is None else max(best, n)
    return best


def ruff_problem(code, st, preview_only, linters):
    """None when ruff runs the code, else a short reason. The more specific selector wins; a tie goes to ignore."""
    sel = specificity(code, st.select, linters)
    ign = specificity(code, st.ignore, linters)
    if sel is None:
        return "not selected"
    if ign is not None and ign >= sel:
        return "ignored by a selector at least as specific as the select entry"
    if preview_only and not st.preview:
        return "preview-only rule and preview is not enabled"
    if preview_only and st.explicit_preview and code not in st.select:
        return "preview-only rule and explicit-preview-rules needs its exact code in select"
    return None


# ---------------------------------------------------------------- table

def read_table(path):
    rows, errors = [], []
    seen = {}
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            f = line.split("\t")
            if len(f) != COLS:
                errors.append("%s:%d: %d columns, expected %d" % (path, n, len(f), COLS))
                continue
            lang, key, name, typ, status, local, reason = [x.strip() for x in f]
            where = "%s:%d (%s %s)" % (path, n, lang, key)
            if lang not in LANGS:
                errors.append("%s: language must be ts or py" % where)
            if typ not in TYPES:
                errors.append("%s: unknown Sonar type %r" % (where, typ))
            if status not in STATUSES:
                errors.append("%s: invalid status %r" % (where, status))
            if not key or not name:
                errors.append("%s: key and name are required" % where)
            if (lang, key) in seen:
                errors.append("%s: duplicate of line %d" % (where, seen[(lang, key)]))
            seen[(lang, key)] = n
            if status in ("partial", "not-covered") and not reason:
                errors.append("%s: status %s needs a reason" % (where, status))
            if status in ("covered", "partial") and local in ("", "-"):
                errors.append("%s: status %s needs a local rule id" % (where, status))
            if status == "not-covered" and local not in ("", "-"):
                errors.append("%s: not-covered row must have local rule '-'" % where)
            rows.append(dict(lang=lang, key=key, name=name, type=typ, status=status,
                             local=local, reason=reason, where=where))
    return rows, errors


def check_gate(row, shared):
    spec = row["local"][len("gate:"):]
    rel, _, needle = spec.partition("#")
    path = os.path.join(shared, rel)
    if not os.path.isfile(path):
        return "%s: gate file missing: %s" % (row["where"], rel)
    if needle:
        with open(path, encoding="utf-8", errors="replace") as fh:
            if needle not in fh.read():
                return "%s: %s does not contain %r" % (row["where"], rel, needle)
    return None


def check_sonar_metadata(row, sonar):
    prefix = {"ts": "typescript:", "py": "python:"}.get(row["lang"])
    if row["key"].startswith("quality-gate:"):
        return None
    if prefix and not row["key"].startswith(prefix):
        return "%s: a %s row must use the %s key prefix" % (row["where"], row["lang"], prefix)
    ent = sonar.get((row["lang"], row["key"].split(":", 1)[-1]))
    if ent is None:
        if "unverified" not in row["reason"].lower():
            return ("%s: key is not in the sonar-rules snapshot; regenerate it (%s) or say 'unverified:' in the reason"
                    % (row["where"], REGEN))
        return None
    if ent[0] != row["type"]:
        return "%s: type is %r in the Sonar metadata, row says %r" % (row["where"], ent[0], row["type"])
    if ent[2] != row["name"]:
        return "%s: name differs from the Sonar metadata title %r" % (row["where"], ent[2])
    return None


def rtc_of(local, sonarjs, tse_rules):
    if local.startswith("sonarjs/"):
        ent = sonarjs.get(local)
        return None if ent is None else ent[2] == "1"
    if local.startswith("@typescript-eslint/"):
        ent = tse_rules.get(local)
        return None if ent is None else ent[0] == "1"
    return None if "/" in local else False


def main():
    root, table = sys.argv[1], sys.argv[2]
    presets = os.path.join(root, "scripts", "sonar-parity-presets")
    scaffold = os.path.join(root, "skills", "scaffold")
    shared = os.path.join(scaffold, "shared")
    rows, errors = read_table(table)
    errors.extend(check_pins(presets, os.path.join(shared, "versions.txt")))

    stacks, stack_fail = {}, {}
    for st in ("nextjs", "vite-react", "nestjs"):
        rel = "%s/template/eslint.config.mjs" % st
        try:
            stacks[st] = eslint_stack(st, os.path.join(scaffold, st, "template", "eslint.config.mjs"), rel, presets)
        except (Unresolved, OSError) as exc:
            stack_fail[st] = str(exc)
            errors.append("cannot resolve %s eslint config statically: %s" % (st, exc))
    ruff_rules = load_snapshot(presets, "ruff-rules").rows
    linters = ruff_linters(ruff_rules)
    try:
        py_state, py_fail = ruff_state(os.path.join(scaffold, "fastapi", "template", "pyproject.toml")), None
        check_selectors(py_state, linters)
    except (Unresolved, OSError) as exc:
        py_state, py_fail = None, str(exc)

    sonarjs = load_snapshot(presets, "sonarjs-recommended").rows
    tse_rules = load_snapshot(presets, "typescript-eslint-rules").rows
    sonar = {}
    with open(os.path.join(presets, "sonar-rules.tsv"), encoding="utf-8") as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if line.startswith("#") or len(f) < 5:
                continue
            sonar[(f[0], f[1])] = (f[2], f[3], f[4])
    typed = [s for s in stacks.values() if s.type_aware]
    untyped = [s for s in ("nextjs", "vite-react", "nestjs") if s not in stacks or not stacks[s].type_aware]

    for row in rows:
        msg = check_sonar_metadata(row, sonar)
        if msg:
            errors.append(msg)
        if row["status"] == "not-covered":
            continue
        local = row["local"]
        if local.startswith("gate:"):
            msg = check_gate(row, shared)
            if msg:
                errors.append(msg)
            continue
        if row["lang"] == "ts":
            if local.startswith("sonarjs/"):
                want = row["key"].split(":", 1)[-1]
                ent = sonarjs.get(local)
                if ent is None or ent[1] != want:
                    errors.append("%s: sonarjs snapshot maps %s to %s, row says %s" % (row["where"], local, ent[1] if ent else None, want))
            rtc = rtc_of(local, sonarjs, tse_rules)
            if rtc is None:
                errors.append("%s: %s is in no snapshot, so whether it needs type information is unknown" % (row["where"], local))
            elif rtc and row["status"] == "covered" and untyped:
                errors.append("%s: %s needs type information but %s lint without it; mark the row partial"
                              % (row["where"], local, ", ".join(untyped)))
            need = [st for st in ("nextjs", "vite-react", "nestjs") if not rtc or st in stack_fail or stacks[st].type_aware]
            for st in need:
                if st in stack_fail:
                    continue
                try:
                    lvl = stacks[st].level(local)
                except Unresolved as exc:
                    errors.append("%s: cannot resolve %s eslint config statically: %s" % (row["where"], st, exc))
                    continue
                if lvl != "error":
                    errors.append("%s: %s is %s in %s, expected error" % (row["where"], local, lvl or "not set", st))
        else:
            if py_fail:
                errors.append("%s: cannot resolve fastapi ruff config statically: %s" % (row["where"], py_fail))
                continue
            for code in (c.strip() for c in local.split(",")):
                info = ruff_rules.get(code)
                if info is None:
                    errors.append("%s: ruff code %s is not in the ruff-rules snapshot" % (row["where"], code))
                    continue
                why = ruff_problem(code, py_state, info[1] == "1", linters)
                if why:
                    errors.append("%s: ruff %s is not enabled in fastapi (%s)" % (row["where"], code, why))
                for pat, codes in py_state.pfi:
                    if any(selector_matches(c, code, linters) for c in codes) and not is_test_glob(pat, py=True):
                        errors.append("%s: per-file-ignores %r disables ruff %s outside test paths" % (row["where"], pat, code))

    for lang in LANGS:
        sub = [r for r in rows if r["lang"] == lang]
        counts = dict((s, len([r for r in sub if r["status"] == s])) for s in STATUSES)
        print("%s: covered %d, partial %d, not-covered %d" % (lang, counts["covered"], counts["partial"], counts["not-covered"]))
        for r in sub:
            if r["status"] == "not-covered":
                print("  not-covered %s: %s" % (r["key"], r["reason"]))
    print("type-aware stacks: %s" % (", ".join(s.name for s in typed) or "none"))
    unverified = [r for r in rows if "unverified" in r["reason"].lower()]
    print("unverified rows: %d" % len(unverified))
    for r in unverified:
        print("  unverified %s %s" % (r["lang"], r["key"]))
    outside = [r for r in rows if (r["lang"], r["key"].split(":", 1)[-1]) in sonar and sonar[(r["lang"], r["key"].split(":", 1)[-1])][1] == "0"]
    if outside:
        print("rows for rules outside Sonar way: %s" % ", ".join(r["key"] for r in outside))
    for s in stacks.values():
        for note in dict.fromkeys(s.notes):
            print("note: " + note)
    if errors:
        for e in errors:
            print("FAIL: " + e)
        print("check-sonar-parity: %d problem(s)" % len(errors))
        return 1
    print("check-sonar-parity: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

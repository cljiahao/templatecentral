"""Check scripts/sonar-parity.tsv against the seeded lint configs. Called by check-sonar-parity.sh.

Static only: no packages are installed and no config is executed. ESLint flat configs are read with a
small JavaScript reader; ruff settings from pyproject.toml; presets (sonarjs, typescript-eslint,
@eslint/js, eslint-config-next) come from the snapshots in scripts/sonar-parity-presets/.
A config form this reader cannot resolve fails the row that needs it. Nothing is assumed enabled.
"""
import os
import re
import sys

LANGS = ("ts", "py")
STATUSES = ("covered", "partial", "not-covered")
TYPES = ("bug", "vulnerability", "code smell", "security hotspot", "quality gate")
COLS = 7


def load_snapshot(presets, name):
    path = os.path.join(presets, name + ".tsv")
    out = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            f = line.split("\t")
            out[f[0]] = (f[1], f[2] if len(f) > 2 else "")
    return out


# ---------------------------------------------------------------- JavaScript reader

class Unresolved(Exception):
    pass


TOKEN = re.compile(
    r"""\s+|//[^\n]*|/\*.*?\*/|(?P<str>'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")|(?P<num>\d+(?:\.\d+)?)"""
    r"""|(?P<id>[A-Za-z_$][\w$]*)|(?P<dots>\.\.\.)|(?P<p>[{}\[\](),:;.=?<>!+\-*/%&|^~@])""",
    re.S,
)


def tokenize(src):
    toks = []
    pos = 0
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m:
            raise Unresolved("unreadable character %r" % src[pos])
        pos = m.end()
        if m.group("str") is not None:
            toks.append(("str", m.group("str")[1:-1]))
        elif m.group("num") is not None:
            toks.append(("num", m.group("num")))
        elif m.group("id") is not None:
            toks.append(("id", m.group("id")))
        elif m.group("dots") is not None:
            toks.append(("p", "..."))
        elif m.group("p") is not None:
            toks.append(("p", m.group("p")))
    return toks


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0
        self.imports = {}
        self.consts = {}
        self.default = None

    def peek(self, off=0):
        return self.t[self.i + off] if self.i + off < len(self.t) else ("eof", "")

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def expect(self, val):
        tok = self.take()
        if tok[1] != val or tok[0] not in ("p", "id"):
            raise Unresolved("expected %s, found %s" % (val, tok[1]))

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
                raise Unresolved("unsupported statement near %r" % tok[1])
        if self.default is None:
            raise Unresolved("no default export")

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
                raise Unresolved("bad import")
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
            elif tok[0] == "p" and tok[1] in "?:=<>!+-*/%&|^~" and tok[1] not in ",)]}":
                raise Unresolved("operator %r in expression" % tok[1])
            else:
                return node

    def args(self, close):
        out = []
        while self.peek() != ("p", close):
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
        raise Unresolved("unexpected %r" % (tok[1],))

    def obj(self):
        members = []
        while self.peek() != ("p", "}"):
            if self.peek() == ("p", "..."):
                self.take()
                members.append(("spread", self.expr()))
            else:
                ktok = self.take()
                if ktok[0] not in ("str", "id"):
                    raise Unresolved("unsupported object key %r" % ktok[1])
                self.expect(":")
                members.append((ktok[1], self.expr()))
            if self.peek() == ("p", ","):
                self.take()
        self.take()
        return ("object", members)


# ---------------------------------------------------------------- ESLint evaluation

def dotted(node):
    if node[0] == "ref":
        return [node[1]]
    if node[0] == "member":
        base = dotted(node[1])
        return base + [node[2]] if base else None
    return None


class Eval:
    def __init__(self, parser, presets):
        self.p = parser
        self.presets = presets
        self.cache = {}

    def snap(self, name):
        if name not in self.cache:
            self.cache[name] = load_snapshot(self.presets, name)
        return self.cache[name]

    def preset_rules(self, path):
        """Rules of a known preset reference, or None when the reference is not a known preset."""
        root = path[0]
        src = self.p.imports.get(root, "")
        joined = ".".join(path[1:])
        if src == "eslint-plugin-sonarjs" and joined in ("configs.recommended", "configs.recommended.rules"):
            return self.snap("sonarjs-recommended")
        if src == "typescript-eslint" and joined == "configs.recommended":
            return self.snap("typescript-eslint-recommended")
        if src == "typescript-eslint" and joined == "configs.recommendedTypeChecked":
            return self.snap("typescript-eslint-recommended-type-checked")
        if src == "@eslint/js" and joined == "configs.recommended":
            return self.snap("eslint-recommended")
        if src == "eslint-config-next/typescript" and len(path) == 1:
            return self.snap("next-typescript")
        return None

    def deref(self, node):
        seen = 0
        while node[0] == "ref" and node[1] in self.p.consts and seen < 20:
            node = self.p.consts[node[1]]
            seen += 1
        return node

    def blocks(self, node, out, files=None):
        """Flatten a config array expression into (is_base, {rule: level}) blocks, in order."""
        node = self.deref(node)
        if node[0] == "array":
            for el in node[1]:
                if el[0] == "spread":
                    self.blocks(el[1], out, files)
                else:
                    self.blocks(el, out, files)
        elif node[0] == "call" and dotted(node[1]) and dotted(node[1])[-1] == "config" \
                and self.p.imports.get(dotted(node[1])[0]) == "typescript-eslint":
            for a in node[2]:
                self.blocks(a[1] if a[0] == "spread" else a, out, files)
        elif node[0] == "object":
            self.object_block(node, out, files)
        else:
            path = dotted(node)
            rules = self.preset_rules(path) if path else None
            if rules is not None:
                out.append((True, {k: v[0] for k, v in rules.items()}))
            # any other reference (for example a plugin recommended set) adds nothing known

    def object_block(self, node, out, inherited_files):
        rules = {}
        files = None
        for key, val in node[1]:
            if key == "spread":
                path = dotted(self.deref(val))
                preset = self.preset_rules(path) if path else None
                if preset is not None and path[-1] != "rules":
                    rules = {k: v[0] for k, v in preset.items()}
                elif isinstance(path, list):
                    pass
            elif key == "files":
                files = self.str_list(val)
            elif key == "rules":
                rules = self.rules_obj(val)
        sub_files = files if files is not None else inherited_files
        for key, val in node[1]:
            if key == "extends":
                self.blocks(val, out, sub_files)
        out.append((self.is_base(sub_files), rules))

    @staticmethod
    def is_base(files):
        return files is None or any(f.startswith("**/") for f in files)

    def str_list(self, node):
        node = self.deref(node)
        if node[0] != "array":
            raise Unresolved("files is not an array literal")
        out = []
        for el in node[1]:
            if el[0] != "str":
                raise Unresolved("files holds a non-literal")
            out.append(el[1])
        return out

    def rules_obj(self, node):
        node = self.deref(node)
        if node[0] != "object":
            raise Unresolved("rules is not an object literal")
        rules = {}
        for key, val in node[1]:
            if key == "spread":
                path = dotted(self.deref(val))
                preset = self.preset_rules(path) if path else None
                if preset is not None:
                    rules.update({k: v[0] for k, v in preset.items()})
                continue
            rules[key] = self.level(val)
        return rules

    def level(self, node):
        node = self.deref(node)
        if node[0] == "array":
            if not node[1]:
                raise Unresolved("empty rule array")
            node = node[1][0]
        if node[0] == "str" and node[1] in ("error", "warn", "off"):
            return node[1]
        if node[0] == "num" and node[1] in ("0", "1", "2"):
            return {"0": "off", "1": "warn", "2": "error"}[node[1]]
        raise Unresolved("rule level is not a literal")


def eslint_levels(path, presets):
    with open(path, encoding="utf-8") as fh:
        parser = Parser(tokenize(fh.read()))
    parser.program()
    out = []
    Eval(parser, presets).blocks(parser.default, out)
    levels = {}
    for base, rules in out:
        if base:
            levels.update(rules)
    return levels


# ---------------------------------------------------------------- ruff

def toml_list(text, key):
    m = re.search(r"^%s\s*=\s*\[(.*?)\]" % re.escape(key), text, re.S | re.M)
    if not m:
        return []
    body = re.sub(r"#[^\n]*", "", m.group(1))
    return re.findall(r'"([^"]*)"', body)


def ruff_state(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r"^\[tool\.ruff\.lint\]\s*\n(.*?)(?=^\[|\Z)", text, re.S | re.M)
    if not m:
        raise Unresolved("no [tool.ruff.lint] table")
    body = m.group(1)
    select = toml_list(body, "select") + toml_list(body, "extend-select")
    ignore = toml_list(body, "ignore") + toml_list(body, "extend-ignore")
    if not select:
        raise Unresolved("no select list (ruff defaults are not assumed)")
    return select, ignore


def ruff_enabled(code, select, ignore):
    on = any(code.startswith(s) for s in select if s != "ALL") or "ALL" in select
    off = any(code.startswith(i) for i in ignore)
    return on and not off


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


def main():
    root = sys.argv[1]
    table = sys.argv[2]
    presets = os.path.join(root, "scripts", "sonar-parity-presets")
    scaffold = os.path.join(root, "skills", "scaffold")
    shared = os.path.join(scaffold, "shared")
    rows, errors = read_table(table)

    ts_stacks = ["nextjs", "vite-react", "nestjs"]
    ts_levels, ts_fail = {}, {}
    for st in ts_stacks:
        cfg = os.path.join(scaffold, st, "template", "eslint.config.mjs")
        try:
            ts_levels[st] = eslint_levels(cfg, presets)
        except (Unresolved, OSError) as exc:
            ts_fail[st] = str(exc)
    py_cfg = os.path.join(scaffold, "fastapi", "template", "pyproject.toml")
    try:
        py_state = ruff_state(py_cfg)
        py_fail = None
    except (Unresolved, OSError) as exc:
        py_state, py_fail = None, str(exc)

    sonarjs = load_snapshot(presets, "sonarjs-recommended")
    sonar_keys = {rule: info[1] for rule, info in sonarjs.items()}

    for row in rows:
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
                have = sonar_keys.get(local)
                if have != want:
                    errors.append("%s: sonarjs snapshot maps %s to %s, row says %s" % (row["where"], local, have, want))
            for st in ts_stacks:
                if st in ts_fail:
                    errors.append("%s: cannot resolve %s eslint config statically: %s" % (row["where"], st, ts_fail[st]))
                    continue
                lvl = ts_levels[st].get(local)
                if lvl != "error":
                    errors.append("%s: %s is %s in %s, expected error" % (row["where"], local, lvl or "not set", st))
        else:
            if py_fail:
                errors.append("%s: cannot resolve fastapi ruff config statically: %s" % (row["where"], py_fail))
                continue
            select, ignore = py_state
            for code in local.split(","):
                if not ruff_enabled(code.strip(), select, ignore):
                    errors.append("%s: ruff %s is not enabled in fastapi" % (row["where"], code.strip()))

    for lang in LANGS:
        sub = [r for r in rows if r["lang"] == lang]
        counts = dict((s, len([r for r in sub if r["status"] == s])) for s in STATUSES)
        print("%s: covered %d, partial %d, not-covered %d" % (lang, counts["covered"], counts["partial"], counts["not-covered"]))
        for r in sub:
            if r["status"] == "not-covered":
                print("  not-covered %s: %s" % (r["key"], r["reason"]))
    if errors:
        for e in errors:
            print("FAIL: " + e)
        print("check-sonar-parity: %d problem(s)" % len(errors))
        return 1
    print("check-sonar-parity: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())

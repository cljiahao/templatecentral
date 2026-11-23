"""Helper of check-duplicate-tests.sh: prints one record per pytest or unittest case."""
import ast
import bisect
import hashlib
import io
import os
import sys
import tokenize

SKIP_TOKENS = {
    tokenize.COMMENT,
    tokenize.NL,
    tokenize.NEWLINE,
    tokenize.INDENT,
    tokenize.DEDENT,
    tokenize.ENDMARKER,
}
FSTRING_MIDDLE = getattr(tokenize, "FSTRING_MIDDLE", None)
FUNCS = (ast.FunctionDef, ast.AsyncFunctionDef)
VERSION = sys.version.split()[0]


def die(message):
    sys.stderr.write("check-duplicate-tests: %s\n" % message)
    sys.exit(2)


def digest(text):
    return hashlib.sha1(text.encode("utf-8", "surrogatepass")).hexdigest()


def is_literal(tok_type, tok_string):
    if tok_type in (tokenize.STRING, tokenize.NUMBER):
        return True
    if FSTRING_MIDDLE is not None and tok_type == FSTRING_MIDDLE:
        return True
    return tok_type == tokenize.NAME and tok_string in ("True", "False")


def is_docstring(node):
    return (
        isinstance(node, ast.Expr)
        and isinstance(node.value, ast.Constant)
        and isinstance(node.value.value, str)
    )


class Source:
    def __init__(self, rel, text):
        self.rel = rel
        if "\0" in text:
            die("%s: contains a NUL byte; remove it or delete the file" % rel)
        self.lines = text.split("\n")
        try:
            self.tree = ast.parse(text, filename=rel)
        except SyntaxError as err:
            die(
                "%s:%s: does not parse under Python %s (%s); use the project interpreter (.venv/bin/python3) "
                "or install a newer Python" % (rel, err.lineno, VERSION, err.msg)
            )
        except (ValueError, RecursionError) as err:
            die("%s: cannot parse under Python %s (%s)" % (rel, VERSION, err))
        try:
            self.tokens = [
                t
                for t in tokenize.generate_tokens(io.StringIO(text).readline)
                if t.type not in SKIP_TOKENS
            ]
        except (tokenize.TokenError, IndentationError) as err:
            die("%s: cannot tokenize under Python %s (%s)" % (rel, VERSION, err))
        self.starts = [t.start for t in self.tokens]
        self.ends = [t.end for t in self.tokens]
        self.parent = {}
        for node in ast.walk(self.tree):
            for child in ast.iter_child_nodes(node):
                self.parent[child] = node

    def char_col(self, row, byte_col):
        line = self.lines[row - 1] if 0 < row <= len(self.lines) else ""
        return len(line.encode("utf-8")[:byte_col].decode("utf-8", "ignore"))

    def span(self, first, last):
        start = (first.lineno, self.char_col(first.lineno, first.col_offset))
        end = (last.end_lineno, self.char_col(last.end_lineno, last.end_col_offset))
        return self.tokens[bisect.bisect_left(self.starts, start) : bisect.bisect_right(self.ends, end)]

    def text_of(self, node):
        # Nodes with no position are read through their children.
        if hasattr(node, "lineno") and hasattr(node, "end_lineno") and node.end_lineno is not None:
            return " ".join(t.string for t in self.span(node, node))
        return " ".join(filter(None, (self.text_of(c) for c in ast.iter_child_nodes(node))))

    def body_tokens(self, func):
        body = func.body
        if body and is_docstring(body[0]):
            body = body[1:]
        if not body:
            return []
        return self.span(body[0], body[-1])


def conftest_context(root, rel, cache):
    parts = []
    directory = os.path.dirname(os.path.join(root, rel))
    root_real = os.path.realpath(root)
    while True:
        path = os.path.join(directory, "conftest.py")
        if path not in cache:
            try:
                with open(path, "rb") as handle:
                    cache[path] = hashlib.sha1(handle.read()).hexdigest()
            except OSError:
                cache[path] = ""
        parts.append(cache[path])
        if os.path.realpath(directory) == root_real or os.path.dirname(directory) == directory:
            break
        directory = os.path.dirname(directory)
    return ",".join(parts)


def parametrize_rows(func):
    """Row texts of every parametrize decorator whose table is a literal list or tuple."""
    rows = []
    for deco in func.decorator_list:
        if not isinstance(deco, ast.Call):
            continue
        target = deco.func
        name = target.attr if isinstance(target, ast.Attribute) else target.id if isinstance(target, ast.Name) else ""
        if name != "parametrize" or len(deco.args) < 2:
            continue
        table = deco.args[1]
        if isinstance(table, (ast.List, ast.Tuple)):
            rows.append(table.elts)
    return rows


def names_in(node, into):
    for sub in ast.walk(node):
        if isinstance(sub, ast.Name):
            into.add(sub.id)
        elif isinstance(sub, ast.Attribute):
            into.add(sub.attr)
    return into


def bound_names(stmt):
    names = set()
    if isinstance(stmt, ast.Import):
        for a in stmt.names:
            names.add(a.asname or a.name.split(".")[0])
    elif isinstance(stmt, ast.ImportFrom):
        for a in stmt.names:
            names.add(a.asname or a.name)
    elif isinstance(stmt, FUNCS + (ast.ClassDef,)):
        names.add(stmt.name)
    elif isinstance(stmt, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
        targets = stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]
        for t in targets:
            for sub in ast.walk(t):
                if isinstance(sub, ast.Name):
                    names.add(sub.id)
                elif isinstance(sub, ast.Attribute):
                    names.add(sub.attr)
    return names


def plain_targets(stmt):
    targets = stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]
    return not any(isinstance(sub, (ast.Attribute, ast.Subscript)) for t in targets for sub in ast.walk(t))


def deco_text(src, deco):
    if isinstance(deco, ast.Call):
        target = deco.func
        name = target.attr if isinstance(target, ast.Attribute) else target.id if isinstance(target, ast.Name) else ""
        if name == "parametrize":
            parts = [src.text_of(deco.func)] + [src.text_of(a) for a in deco.args]
            return " ".join(parts + [src.text_of(k) for k in deco.keywords if k.arg != "ids"])
    return src.text_of(deco)


IMPLICIT = ("setup", "set_up", "teardown", "tear_down")


def arg_names(func):
    a = func.args
    names = [x.arg for x in a.posonlyargs + a.args + a.kwonlyargs]
    if names and names[0] in ("self", "cls"):
        names = names[1:]
    if a.vararg:
        names.append("*" + a.vararg.arg)
    if a.kwarg:
        names.append("**" + a.kwarg.arg)
    return ",".join(names)


def is_test_class(node):
    if node.name.startswith("Test"):
        return True
    for base in node.bases:
        name = base.id if isinstance(base, ast.Name) else base.attr if isinstance(base, ast.Attribute) else ""
        if name.endswith("TestCase"):
            return True
    return False


def collect(tree):
    """Test functions at module level, in test classes, and under if, try, with, for, while and match."""
    found = []

    def walk(node):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, FUNCS):
                if child.name.startswith("test"):
                    found.append(child)
            elif isinstance(child, ast.ClassDef):
                if is_test_class(child):
                    walk(child)
            elif isinstance(child, ast.stmt) or isinstance(child, (ast.ExceptHandler, getattr(ast, "match_case", ()))):
                walk(child)

    walk(tree)
    return found


def main():
    if len(sys.argv) != 3:
        die("usage: duplicate_tests_py.py <project-root> <file-list>")
    if sys.version_info < (3, 8):
        die("Python %s is too old: install the Python version this project pins" % VERSION)
    root, list_file = sys.argv[1], sys.argv[2]
    with open(list_file, "rb") as handle:
        rels = [r for r in handle.read().decode("utf-8", "surrogateescape").split("\0") if r]
    cache = {}
    out = []
    for rel in rels:
        path = os.path.join(root, rel)
        try:
            with open(path, "rb") as handle:
                handle.read(0)
            with tokenize.open(path) as handle:
                text = handle.read()
        except (OSError, SyntaxError, UnicodeDecodeError):
            die("cannot read %s" % rel)
        src = Source(rel, text)
        conf = conftest_context(root, rel, cache)
        cases = collect(src.tree)
        holders = set()
        for func in cases:
            node = func
            while node is not None:
                holders.add(node)
                node = src.parent.get(node)
        statement_memo = {}

        def statements_of(node):
            if node in statement_memo:
                return statement_memo[node]
            items = []
            for child in ast.iter_child_nodes(node):
                if child in holders:
                    continue
                is_stmt = isinstance(child, ast.stmt) and isinstance(node, (ast.Module, ast.ClassDef))
                if not is_stmt:
                    continue
                if is_docstring(child) and child is node.body[0]:
                    continue
                names = bound_names(child)
                always = False
                if isinstance(child, (ast.Import, ast.ImportFrom)):
                    always = False
                elif isinstance(child, FUNCS):
                    lower = child.name.lower()
                    always = lower.startswith(IMPLICIT) or any(
                        isinstance(sub, ast.keyword) and sub.arg == "autouse" for deco in child.decorator_list for sub in ast.walk(deco)
                    )
                elif isinstance(child, ast.ClassDef):
                    always = False
                elif isinstance(child, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
                    always = "pytestmark" in names or not plain_targets(child)
                else:
                    always = True
                used = set()
                for part in ast.walk(child):
                    if isinstance(part, ast.Name):
                        used.add(part.id)
                    elif isinstance(part, ast.Attribute):
                        used.add(part.attr)
                text = src.text_of(child)
                if isinstance(child, ast.ImportFrom) and child.level:
                    up = os.path.join(os.path.dirname(rel), *([".."] * (child.level - 1)))
                    text = "%s@%s" % (text, os.path.normpath(up))
                items.append({"names": names, "used": used, "always": always, "text": text, "on": False})
            statement_memo[node] = items
            return items

        other_memo = {}

        def other_context(node):
            # Parts of a node that are not statements of its body: decorators, bases, headers, loop data, conditions.
            if node in other_memo:
                return other_memo[node]
            parts = []
            for child in ast.iter_child_nodes(node):
                if child in holders:
                    continue
                if isinstance(child, ast.stmt) and isinstance(node, (ast.Module, ast.ClassDef)):
                    continue
                parts.append(src.text_of(child))
            other_memo[node] = "\n".join(parts)
            return other_memo[node]

        def case_context(chain, refs):
            scopes = [statements_of(n) for n in chain if isinstance(n, (ast.Module, ast.ClassDef))]
            for items in scopes:
                for item in items:
                    item["on"] = item["always"]
                    if item["on"]:
                        refs.update(item["used"])
            grew = True
            while grew:
                grew = False
                for items in scopes:
                    for item in items:
                        if item["on"] or not (item["names"] & refs):
                            continue
                        item["on"] = True
                        grew = True
                        refs.update(item["used"])
            parts = []
            for node in chain:
                texts = [other_context(node)]
                if isinstance(node, (ast.Module, ast.ClassDef)):
                    texts.append("\n".join(i["text"] for i in statements_of(node) if i["on"]))
                parts.append("\n".join(t for t in texts if t))
            return "\n\x03\n".join(p for p in parts if p)

        for func in cases:
            chain = []
            node = src.parent.get(func)
            while node is not None:
                chain.append(node)
                node = src.parent.get(node)
            chain.reverse()
            refs = names_in(func, set())
            refs.update(a.strip("*") for a in arg_names(func).split(",") if a)
            for deco in func.decorator_list:
                for sub in ast.walk(deco):
                    if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
                        refs.add(sub.value)
            for anc in chain:
                for kid in ast.iter_child_nodes(anc):
                    if kid not in holders and not (isinstance(kid, ast.stmt) and isinstance(anc, (ast.Module, ast.ClassDef))):
                        names_in(kid, refs)
            ctx_inner = case_context(chain, refs)
            for table in parametrize_rows(func):
                seen_rows = set()
                for elt in table:
                    row = src.text_of(elt)
                    if row in seen_rows:
                        out.append("\t".join(["R", rel, str(func.lineno), "0", "-", "-"]))
                        break
                    seen_rows.add(row)
            toks = src.body_tokens(func)
            decorators = "\n".join(deco_text(src, d) for d in func.decorator_list)
            ctx = "%s\n\x03\n%s\n%s\n%s" % (conf, ctx_inner, decorators, arg_names(func))
            exact = "\x02".join(t.string for t in toks)
            shape = "\x02".join("\x01L" if is_literal(t.type, t.string) else t.string for t in toks)
            out.append(
                "\t".join(
                    ["C", rel, str(func.lineno), str(len(toks)), digest(ctx + "\x00" + exact), digest(ctx + "\x00" + shape)]
                )
            )
    sys.stdout.write("".join(line + "\n" for line in out))


try:
    main()
except SystemExit:
    raise
except Exception as err:
    die("internal error under Python %s: %s: %s" % (VERSION, type(err).__name__, err))

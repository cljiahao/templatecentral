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


def has_parametrize(func):
    for deco in func.decorator_list:
        for node in ast.walk(deco):
            if isinstance(node, ast.Attribute) and node.attr == "parametrize":
                return True
            if isinstance(node, ast.Name) and node.id == "parametrize":
                return True
    return False


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
        die("Python %s is too old: the check needs Python 3.8 or newer" % VERSION)
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
        memo = {}

        def context_of(node):
            if node in memo:
                return memo[node]
            parts = []
            first = True
            for child in ast.iter_child_nodes(node):
                skip = child in holders or (first and is_docstring(child) and isinstance(node, (ast.Module, ast.ClassDef)))
                if isinstance(node, (ast.Module, ast.ClassDef)):
                    first = False
                if skip:
                    continue
                text = src.text_of(child)
                if isinstance(child, ast.ImportFrom) and child.level:
                    up = os.path.join(os.path.dirname(rel), *([".."] * (child.level - 1)))
                    text = "%s@%s" % (text, os.path.normpath(up))
                parts.append(text)
            memo[node] = "\n".join(parts)
            return memo[node]

        for func in cases:
            if has_parametrize(func):
                out.append("\t".join(["P", rel, str(func.lineno), "0", "-", "-"]))
                continue
            chain = []
            node = src.parent.get(func)
            while node is not None:
                chain.append(node)
                node = src.parent.get(node)
            chain.reverse()
            toks = src.body_tokens(func)
            decorators = "\n".join(src.text_of(d) for d in func.decorator_list)
            ctx = "%s\n\x03\n%s\n%s\n%s" % (conf, "\n\x03\n".join(c for c in map(context_of, chain) if c), decorators, arg_names(func))
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

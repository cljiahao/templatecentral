"""Helper of check-duplicate-tests.sh: prints one record per pytest case."""
import ast
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
SETUP_METHODS = {"setup_method", "setup_class", "setUp", "setUpClass", "teardown_method", "teardown_class", "tearDown"}
FSTRING_MIDDLE = getattr(tokenize, "FSTRING_MIDDLE", None)


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


class Source:
    def __init__(self, rel, text):
        self.rel = rel
        self.lines = text.splitlines(True)
        try:
            self.tree = ast.parse(text, filename=rel)
        except SyntaxError as err:
            die("%s:%s: does not parse (%s)" % (rel, err.lineno, err.msg))
        try:
            self.tokens = [
                t
                for t in tokenize.generate_tokens(io.StringIO(text).readline)
                if t.type not in SKIP_TOKENS
            ]
        except (tokenize.TokenError, IndentationError) as err:
            die("%s: cannot tokenize (%s)" % (rel, err))

    def char_col(self, row, byte_col):
        line = self.lines[row - 1] if row - 1 < len(self.lines) else ""
        return len(line.encode("utf-8")[:byte_col].decode("utf-8", "ignore"))

    def span(self, first, last):
        start = (first.lineno, self.char_col(first.lineno, first.col_offset))
        end = (last.end_lineno, self.char_col(last.end_lineno, last.end_col_offset))
        return [t for t in self.tokens if t.start >= start and t.end <= end]

    def body_tokens(self, func):
        body = func.body
        if (
            body
            and isinstance(body[0], ast.Expr)
            and isinstance(body[0].value, ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            body = body[1:]
        if not body:
            return []
        return self.span(body[0], body[-1])

    def text_of(self, nodes):
        if not nodes:
            return ""
        return "\n".join(" ".join(t.string for t in self.span(n, n)) for n in nodes)


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


def cases(tree):
    """Yield each test function with the setup methods of its enclosing test classes."""
    funcs = (ast.FunctionDef, ast.AsyncFunctionDef)

    def walk(body, setup):
        for node in body:
            if isinstance(node, funcs) and node.name.startswith("test"):
                if node.name.startswith("test_") or node.name == "test":
                    yield node, setup
            elif isinstance(node, ast.ClassDef) and node.name.startswith("Test"):
                own = [n for n in node.body if isinstance(n, funcs) and n.name in SETUP_METHODS]
                yield from walk_class(node.body, setup + own)

    def walk_class(body, setup):
        for node in body:
            if isinstance(node, funcs) and node.name.startswith("test_"):
                yield node, setup
            elif isinstance(node, ast.ClassDef) and node.name.startswith("Test"):
                own = [n for n in node.body if isinstance(n, funcs) and n.name in SETUP_METHODS]
                yield from walk_class(node.body, setup + own)

    return walk(tree.body, [])


def main():
    if len(sys.argv) != 3:
        die("usage: duplicate_tests_py.py <project-root> <file-list>")
    root, list_file = sys.argv[1], sys.argv[2]
    with open(list_file, "rb") as handle:
        rels = [r for r in handle.read().decode("utf-8", "surrogateescape").split("\0") if r]
    cache = {}
    out = []
    for rel in rels:
        try:
            with open(os.path.join(root, rel), "rb") as handle:
                raw = handle.read()
            text = tokenize.open(os.path.join(root, rel)).read() if raw else ""
        except (OSError, SyntaxError, UnicodeDecodeError):
            die("cannot read %s" % rel)
        src = Source(rel, text)
        conf = conftest_context(root, rel, cache)
        for func, setup in cases(src.tree):
            if has_parametrize(func):
                continue
            toks = src.body_tokens(func)
            decorators = src.text_of(func.decorator_list)
            ctx = "%s\n%s\n%s\n%s" % (conf, decorators, arg_names(func), src.text_of(setup))
            exact = "\x02".join(t.string for t in toks)
            shape = "\x02".join("\x01L" if is_literal(t.type, t.string) else t.string for t in toks)
            out.append(
                "\t".join(
                    [rel, str(func.lineno), str(len(toks)), digest(ctx + "\x00" + exact), digest(ctx + "\x00" + shape)]
                )
            )
    sys.stdout.write("".join(line + "\n" for line in out))


main()

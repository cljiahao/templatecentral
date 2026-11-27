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
        if hasattr(node, "lineno") and hasattr(node, "end_lineno") and node.end_lineno is not None:
            return " ".join(t.string for t in self.span(node, node))
        return " ".join(filter(None, (self.text_of(c) for c in ast.iter_child_nodes(node))))

    def text_ids(self, node):
        if not (hasattr(node, "lineno") and node.end_lineno is not None):
            return self.text_of(node)
        lo = bisect.bisect_left(self.starts, (node.lineno, self.char_col(node.lineno, node.col_offset)))
        hi = bisect.bisect_right(self.ends, (node.end_lineno, self.char_col(node.end_lineno, node.end_col_offset)))
        drop = set()
        for sub in ast.walk(node):
            if not isinstance(sub, ast.Call):
                continue
            target = sub.func
            if (target.attr if isinstance(target, ast.Attribute) else target.id if isinstance(target, ast.Name) else "") != "param":
                continue
            for kw in sub.keywords:
                if kw.arg == "id":
                    v = kw.value
                    first = bisect.bisect_left(self.starts, (v.lineno, self.char_col(v.lineno, v.col_offset)))
                    last = bisect.bisect_right(self.ends, (v.end_lineno, self.char_col(v.end_lineno, v.end_col_offset)))
                    drop.update(range(first - 3, last))
        return " ".join(self.tokens[i].string for i in range(lo, hi) if i not in drop)

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


def binds_locally(scope, name):
    """True when a function or lambda binds name as a parameter or local, unless it declares the name global."""
    args = scope.args
    params = args.posonlyargs + args.args + args.kwonlyargs + [a for a in (args.vararg, args.kwarg) if a]
    if any(a.arg == name for a in params):
        return True
    if isinstance(scope, ast.Lambda):
        return False
    todo = list(scope.body)
    bound = False
    while todo:
        n = todo.pop()
        if isinstance(n, (ast.Global, ast.Nonlocal)) and name in n.names:
            return False
        if isinstance(n, FUNCS + (ast.ClassDef,)):
            bound = bound or n.name == name
            continue
        if isinstance(n, ast.Name) and n.id == name and isinstance(n.ctx, (ast.Store, ast.Del)):
            bound = True
        if isinstance(n, ast.alias) and (n.asname or n.name.split(".")[0]) == name:
            bound = True
        if isinstance(n, ast.ExceptHandler) and n.name == name:
            bound = True
        todo.extend(ast.iter_child_nodes(n))
    return bound


def only_plain_reads(tree, name, target):
    """True when every reference to the module-level name is its one assignment target, a parametrize table argument, len(name) or a loop or comprehension source."""
    allowed = {id(target)}
    for n in ast.walk(tree):
        if isinstance(n, FUNCS + (ast.ClassDef,)):
            for deco in n.decorator_list:
                f = deco.func if isinstance(deco, ast.Call) else None
                fname = f.attr if isinstance(f, ast.Attribute) else f.id if isinstance(f, ast.Name) else ""
                if fname == "parametrize" and len(deco.args) >= 2 and isinstance(deco.args[1], ast.Name) and deco.args[1].id == name:
                    allowed.add(id(deco.args[1]))
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "len" and len(n.args) == 1 and not n.keywords:
            if isinstance(n.args[0], ast.Name) and n.args[0].id == name:
                allowed.add(id(n.args[0]))
        iters = [n.iter] if isinstance(n, (ast.For, ast.AsyncFor, ast.comprehension)) else []
        for it in iters:
            if isinstance(it, ast.Name) and it.id == name:
                allowed.add(id(it))
    ok = [True]

    def visit(n):
        if not ok[0]:
            return
        if isinstance(n, ast.Name) and n.id == name and id(n) not in allowed:
            ok[0] = False
            return
        if isinstance(n, FUNCS + (ast.Lambda,)):
            outer = list(n.decorator_list) if isinstance(n, FUNCS) else []
            outer += list(n.args.defaults) + [d for d in n.args.kw_defaults if d is not None]
            for o in outer:
                visit(o)
            if not binds_locally(n, name):
                for b in (n.body if isinstance(n.body, list) else [n.body]):
                    visit(b)
            return
        if isinstance(n, ast.ClassDef):
            for o in list(n.decorator_list) + list(n.bases) + [k.value for k in n.keywords]:
                visit(o)
            class_binds = any(
                isinstance(x, ast.Name) and x.id == name and isinstance(x.ctx, ast.Store)
                for st in n.body if not isinstance(st, FUNCS + (ast.ClassDef,))
                for x in ast.walk(st)
            )
            for st in n.body:
                if not class_binds or isinstance(st, FUNCS + (ast.ClassDef,)):
                    visit(st)
            return
        if isinstance(n, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
            if any(isinstance(x, ast.Name) and x.id == name for g in n.generators for x in ast.walk(g.target)):
                visit(n.generators[0].iter)
                return
        for kid in ast.iter_child_nodes(n):
            visit(kid)

    visit(tree)
    return ok[0]


def module_table(tree, name):
    """The list or tuple literal a module-level name is assigned once and only read afterwards, or None."""
    hits = [st for st in tree.body if name in bound_names(st)]
    if len(hits) != 1:
        return None
    st = hits[0]
    value = st.value if isinstance(st, (ast.Assign, ast.AnnAssign)) else None
    targets = st.targets if isinstance(st, ast.Assign) else [st.target] if isinstance(st, ast.AnnAssign) else []
    if len(targets) != 1 or not isinstance(targets[0], ast.Name) or not isinstance(value, (ast.List, ast.Tuple)):
        return None
    if not only_plain_reads(tree, name, targets[0]):
        return None
    return value.elts


def parametrize_rows(func, tree):
    """Row nodes of every parametrize decorator whose table is a literal list or tuple, or one module-level constant of that kind."""
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
        elif isinstance(table, ast.Name):
            elts = module_table(tree, table.id)
            if elts is not None:
                rows.append(elts)
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


def has_effect(value):
    """True when evaluating the value calls something or awaits; a lambda body does not run."""
    stack = [value]
    while stack:
        n = stack.pop()
        if isinstance(n, (ast.Call, ast.Await)):
            return True
        if not isinstance(n, ast.Lambda):
            stack.extend(ast.iter_child_nodes(n))
    return False


def deco_text(src, deco):
    if isinstance(deco, ast.Call):
        target = deco.func
        name = target.attr if isinstance(target, ast.Attribute) else target.id if isinstance(target, ast.Name) else ""
        if name == "parametrize":
            parts = [src.text_of(deco.func)] + [src.text_ids(a) for a in deco.args]
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
        die("Python %s is too old: this check needs python 3.8 or newer; use the project's .venv/bin/python3 or install a newer Python" % VERSION)
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
        below = {}
        for func in cases:
            ids = names_in(func, set())
            ids.update(a.strip("*") for a in arg_names(func).split(",") if a)
            node = src.parent.get(func)
            while node is not None:
                below.setdefault(node, set()).update(ids)
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
                    always = "pytestmark" in names or not plain_targets(child) or (
                        child.value is not None and has_effect(child.value) and not (names & below.get(node, set()))
                    )
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
            for table in parametrize_rows(func, src.tree):
                seen_rows = set()
                for elt in table:
                    row = src.text_ids(elt)
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

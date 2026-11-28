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
                "%s:%s: does not parse under Python %s (%s); repair the syntax error, "
                "or put a newer python3 first on the path" % (rel, err.lineno, VERSION, err.msg)
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

    def value_range(self, v):
        """Returns the token indexes of a value, with the three tokens before it."""
        first = bisect.bisect_left(self.starts, (v.lineno, self.char_col(v.lineno, v.col_offset)))
        last = bisect.bisect_right(self.ends, (v.end_lineno, self.char_col(v.end_lineno, v.end_col_offset)))
        return range(first - 3, last)

    def id_tokens(self, node):
        """Returns the token indexes of the id= values of every param call under the node."""
        drop = set()
        for sub in ast.walk(node):
            if isinstance(sub, ast.Call) and callee_name(sub.func) == "param":
                for kw in sub.keywords:
                    if kw.arg == "id":
                        drop.update(self.value_range(kw.value))
        return drop

    def text_ids(self, node):
        if not (hasattr(node, "lineno") and node.end_lineno is not None):
            return self.text_of(node)
        lo = bisect.bisect_left(self.starts, (node.lineno, self.char_col(node.lineno, node.col_offset)))
        hi = bisect.bisect_right(self.ends, (node.end_lineno, self.char_col(node.end_lineno, node.end_col_offset)))
        drop = self.id_tokens(node)
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


def callee_name(node):
    """Returns the attribute or plain name of a callee, else an empty string."""
    return node.attr if isinstance(node, ast.Attribute) else node.id if isinstance(node, ast.Name) else ""


def node_binds(n, name):
    """True when the node itself binds the name as a def, class, store, import or except target."""
    if isinstance(n, FUNCS + (ast.ClassDef,)):
        return n.name == name
    if isinstance(n, ast.Name):
        return n.id == name and isinstance(n.ctx, (ast.Store, ast.Del))
    if isinstance(n, ast.alias):
        return (n.asname or n.name.split(".")[0]) == name
    return isinstance(n, ast.ExceptHandler) and n.name == name


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
        bound = node_binds(n, name) or bound
        if not isinstance(n, FUNCS + (ast.ClassDef,)):
            todo.extend(ast.iter_child_nodes(n))
    return bound


def is_name(node, name):
    """True when the node is a plain reference to the name."""
    return isinstance(node, ast.Name) and node.id == name


def parametrize_table_arg(deco, name):
    """Returns the table argument of a parametrize decorator when it is the name, else None."""
    f = deco.func if isinstance(deco, ast.Call) else None
    if callee_name(f) == "parametrize" and len(deco.args) >= 2 and is_name(deco.args[1], name):
        return deco.args[1]
    return None


def table_arg_ids(tree, name):
    """Returns the ids of the parametrize table arguments that are the name."""
    allowed = set()
    for n in ast.walk(tree):
        if isinstance(n, FUNCS + (ast.ClassDef,)):
            for deco in n.decorator_list:
                arg = parametrize_table_arg(deco, name)
                if arg is not None:
                    allowed.add(id(arg))
    return allowed


def read_ids(n, name):
    """Returns the ids of the name nodes in len(name) and in a loop or comprehension source."""
    ids = set()
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "len" and len(n.args) == 1 and not n.keywords and is_name(n.args[0], name):
        ids.add(id(n.args[0]))
    if isinstance(n, (ast.For, ast.AsyncFor, ast.comprehension)) and is_name(n.iter, name):
        ids.add(id(n.iter))
    return ids


def class_binds_name(n, name):
    """True when a class body outside its methods stores the name."""
    return any(
        isinstance(x, ast.Name) and x.id == name and isinstance(x.ctx, ast.Store)
        for st in n.body if not isinstance(st, FUNCS + (ast.ClassDef,))
        for x in ast.walk(st)
    )


class ReadCheck:
    """Walks a tree and records whether the name is read anywhere except an allowed place."""

    def __init__(self, name, allowed):
        self.name = name
        self.allowed = allowed
        self.ok = True

    def visit(self, n):
        """Visits one node, honouring the scopes that rebind the name."""
        if not self.ok:
            return
        if is_name(n, self.name) and id(n) not in self.allowed:
            self.ok = False
        elif isinstance(n, FUNCS + (ast.Lambda,)):
            self.visit_function(n)
        elif isinstance(n, ast.ClassDef):
            self.visit_class(n)
        elif not self.visit_comprehension(n):
            for kid in ast.iter_child_nodes(n):
                self.visit(kid)

    def visit_function(self, n):
        """Visits the decorators and defaults, then the body unless the function binds the name."""
        outer = list(n.decorator_list) if isinstance(n, FUNCS) else []
        outer += list(n.args.defaults) + [d for d in n.args.kw_defaults if d is not None]
        for o in outer:
            self.visit(o)
        if not binds_locally(n, self.name):
            for b in (n.body if isinstance(n.body, list) else [n.body]):
                self.visit(b)

    def visit_class(self, n):
        """Visits the decorators, bases and keywords, then the body, which may rebind the name."""
        for o in list(n.decorator_list) + list(n.bases) + [k.value for k in n.keywords]:
            self.visit(o)
        class_binds = class_binds_name(n, self.name)
        for st in n.body:
            if not class_binds or isinstance(st, FUNCS + (ast.ClassDef,)):
                self.visit(st)

    def visit_comprehension(self, n):
        """Visits only the first source of a comprehension that rebinds the name; returns True when it did."""
        if not isinstance(n, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
            return False
        if any(is_name(x, self.name) for g in n.generators for x in ast.walk(g.target)):
            self.visit(n.generators[0].iter)
            return True
        return False


def only_plain_reads(tree, name, target):
    """True when every reference to the module-level name is its one assignment target, a parametrize table argument, len(name) or a loop or comprehension source."""
    allowed = {id(target)} | table_arg_ids(tree, name)
    for n in ast.walk(tree):
        allowed |= read_ids(n, name)
    check = ReadCheck(name, allowed)
    check.visit(tree)
    return check.ok


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


def table_elts(table, tree):
    """Returns the rows of a literal table, or of a module-level constant of that kind, else None."""
    if isinstance(table, (ast.List, ast.Tuple)):
        return table.elts
    if isinstance(table, ast.Name):
        return module_table(tree, table.id)
    return None


def parametrize_rows(func, tree):
    """Row nodes of every parametrize decorator whose table is a literal list or tuple, or one module-level constant of that kind."""
    rows = []
    for deco in func.decorator_list:
        if not isinstance(deco, ast.Call) or callee_name(deco.func) != "parametrize" or len(deco.args) < 2:
            continue
        elts = table_elts(deco.args[1], tree)
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
    """Returns the names a top-level statement binds."""
    if isinstance(stmt, ast.Import):
        return {a.asname or a.name.split(".")[0] for a in stmt.names}
    if isinstance(stmt, ast.ImportFrom):
        return {a.asname or a.name for a in stmt.names}
    if isinstance(stmt, FUNCS + (ast.ClassDef,)):
        return {stmt.name}
    names = set()
    if isinstance(stmt, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
        targets = stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]
        for t in targets:
            names_in(t, names)
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
    """Returns the decorator text, leaving the ids keyword of parametrize out."""
    if isinstance(deco, ast.Call) and callee_name(deco.func) == "parametrize":
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
    """True for a class named Test* or based on a *TestCase."""
    return node.name.startswith("Test") or any(callee_name(base).endswith("TestCase") for base in node.bases)


def descends(child):
    """True for a child the test collector walks into: a test class, or a statement, handler or case."""
    if isinstance(child, ast.ClassDef):
        return is_test_class(child)
    return isinstance(child, ast.stmt) or isinstance(child, (ast.ExceptHandler, getattr(ast, "match_case", ())))


def collect_into(node, found):
    """Appends the test functions under the node."""
    for child in ast.iter_child_nodes(node):
        if isinstance(child, FUNCS):
            if child.name.startswith("test"):
                found.append(child)
        elif descends(child):
            collect_into(child, found)


def collect(tree):
    """Test functions at module level, in test classes, and under if, try, with, for, while and match."""
    found = []
    collect_into(tree, found)
    return found


def ancestors(src, node):
    """Returns the parents of the node, nearest first."""
    chain = []
    node = src.parent.get(node)
    while node is not None:
        chain.append(node)
        node = src.parent.get(node)
    return chain


def func_refs(func):
    """Returns the names a test function uses, and its argument names."""
    refs = names_in(func, set())
    refs.update(a.strip("*") for a in arg_names(func).split(",") if a)
    return refs


def implicit_function(fn):
    """True for a setup or teardown function, or one with an autouse keyword in a decorator."""
    return fn.name.lower().startswith(IMPLICIT) or any(
        isinstance(sub, ast.keyword) and sub.arg == "autouse" for deco in fn.decorator_list for sub in ast.walk(deco)
    )


def has_duplicate_row(src, table):
    """True when two rows of a parametrize table have the same tokens, ids left out."""
    seen_rows = set()
    for elt in table:
        row = src.text_ids(elt)
        if row in seen_rows:
            return True
        seen_rows.add(row)
    return False


def grow_once(scopes, refs):
    """Switches on every statement that binds a referenced name; returns True when one was switched on."""
    grew = False
    for item in (i for items in scopes for i in items):
        if not item["on"] and item["names"] & refs:
            item["on"] = True
            grew = True
            refs.update(item["used"])
    return grew


class FileScan:
    """The records of one Python test file, with the shared context of its test cases."""

    def __init__(self, rel, src, cases):
        self.rel = rel
        self.src = src
        self.cases = cases
        self.holders = set()
        self.below = {}
        for func in cases:
            parents = ancestors(src, func)
            self.holders.add(func)
            self.holders.update(parents)
            ids = func_refs(func)
            for node in parents:
                self.below.setdefault(node, set()).update(ids)
        self.statement_memo = {}
        self.other_memo = {}

    def always_on(self, node, child, names):
        """True for a statement every test case needs: a fixture hook, a marker, or a call nothing else uses."""
        if isinstance(child, (ast.Import, ast.ImportFrom, ast.ClassDef)):
            return False
        if isinstance(child, FUNCS):
            return implicit_function(child)
        if isinstance(child, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            return "pytestmark" in names or not plain_targets(child) or (
                child.value is not None and has_effect(child.value) and not (names & self.below.get(node, set()))
            )
        return True

    def statement_text(self, child):
        """Returns the tokens of a statement, with the package folder a relative import points at."""
        text = self.src.text_of(child)
        if isinstance(child, ast.ImportFrom) and child.level:
            up = os.path.join(os.path.dirname(self.rel), *([".."] * (child.level - 1)))
            text = "%s@%s" % (text, os.path.normpath(up))
        return text

    def statement_item(self, node, child):
        """Returns the record of a module or class statement that is not a test, or None."""
        if child in self.holders or not (isinstance(child, ast.stmt) and isinstance(node, (ast.Module, ast.ClassDef))):
            return None
        if is_docstring(child) and child is node.body[0]:
            return None
        names = bound_names(child)
        return {"names": names, "used": names_in(child, set()), "always": self.always_on(node, child, names), "text": self.statement_text(child), "on": False}

    def statements_of(self, node):
        """Returns the statement records of a module or class, once."""
        if node in self.statement_memo:
            return self.statement_memo[node]
        items = []
        for child in ast.iter_child_nodes(node):
            item = self.statement_item(node, child)
            if item is not None:
                items.append(item)
        self.statement_memo[node] = items
        return items

    def other_context(self, node):
        """Returns the tokens of the children of a node that are neither tests nor module or class statements, once."""
        if node in self.other_memo:
            return self.other_memo[node]
        parts = []
        for child in ast.iter_child_nodes(node):
            if child in self.holders:
                continue
            if isinstance(child, ast.stmt) and isinstance(node, (ast.Module, ast.ClassDef)):
                continue
            parts.append(self.src.text_of(child))
        self.other_memo[node] = "\n".join(parts)
        return self.other_memo[node]

    def case_context(self, chain, refs):
        """Returns the tokens of the statements a test case depends on, from the module down to its class."""
        scopes = [self.statements_of(n) for n in chain if isinstance(n, (ast.Module, ast.ClassDef))]
        for item in (i for items in scopes for i in items):
            item["on"] = item["always"]
            if item["on"]:
                refs.update(item["used"])
        while grow_once(scopes, refs):
            pass
        parts = []
        for node in chain:
            texts = [self.other_context(node)]
            if isinstance(node, (ast.Module, ast.ClassDef)):
                texts.append("\n".join(i["text"] for i in self.statements_of(node) if i["on"]))
            parts.append("\n".join(t for t in texts if t))
        return "\n\x03\n".join(p for p in parts if p)

    def case_refs(self, func, chain):
        """Returns the names and strings a test case may depend on."""
        refs = func_refs(func)
        refs.update(sub.value for deco in func.decorator_list for sub in ast.walk(deco) if isinstance(sub, ast.Constant) and isinstance(sub.value, str))
        for anc in chain:
            for kid in ast.iter_child_nodes(anc):
                if not self.is_context_child(anc, kid):
                    names_in(kid, refs)
        return refs

    def is_context_child(self, anc, kid):
        """True for a test, or a module or class statement, which the context handles apart."""
        return kid in self.holders or (isinstance(kid, ast.stmt) and isinstance(anc, (ast.Module, ast.ClassDef)))

    def case_records(self, func, conf):
        """Returns the duplicate-row records and the case record of one test function."""
        chain = ancestors(self.src, func)[::-1]
        ctx_inner = self.case_context(chain, self.case_refs(func, chain))
        out = ["\t".join(["R", self.rel, str(func.lineno), "0", "-", "-"]) for table in parametrize_rows(func, self.src.tree) if has_duplicate_row(self.src, table)]
        toks = self.src.body_tokens(func)
        decorators = "\n".join(deco_text(self.src, d) for d in func.decorator_list)
        ctx = "%s\n\x03\n%s\n%s\n%s" % (conf, ctx_inner, decorators, arg_names(func))
        exact = "\x02".join(t.string for t in toks)
        shape = "\x02".join("\x01L" if is_literal(t.type, t.string) else t.string for t in toks)
        out.append("\t".join(["C", self.rel, str(func.lineno), str(len(toks)), digest(ctx + "\x00" + exact), digest(ctx + "\x00" + shape)]))
        return out

    def records(self, conf):
        """Returns the output lines of every test case of the file."""
        out = []
        for func in self.cases:
            out.extend(self.case_records(func, conf))
        return out


def read_test_file(root, rel):
    """Returns the decoded text of a test file, or stops with exit 2 when it cannot be read."""
    path = os.path.join(root, rel)
    try:
        with open(path, "rb") as handle:
            handle.read(0)
        with tokenize.open(path) as handle:
            return handle.read()
    except (OSError, SyntaxError, UnicodeDecodeError):
        die("cannot read %s" % rel)


def main():
    if len(sys.argv) != 3:
        die("usage: duplicate_tests_py.py <project-root> <file-list>")
    if sys.version_info < (3, 8):
        die("Python %s is too old: this check needs python 3.8 or newer; install a newer Python 3 on the path" % VERSION)
    root, list_file = sys.argv[1], sys.argv[2]
    with open(list_file, "rb") as handle:
        rels = [r for r in handle.read().decode("utf-8", "surrogateescape").split("\0") if r]
    cache = {}
    out = []
    for rel in rels:
        src = Source(rel, read_test_file(root, rel))
        conf = conftest_context(root, rel, cache)
        out.extend(FileScan(rel, src, collect(src.tree)).records(conf))
    sys.stdout.write("".join(line + "\n" for line in out))


try:
    main()
except SystemExit:
    raise
except Exception as err:
    die("internal error under Python %s: %s: %s" % (VERSION, type(err).__name__, err))

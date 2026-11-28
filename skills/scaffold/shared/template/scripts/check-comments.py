"""Python reader for check-comments.sh: path and ranges on stdin, one finding per line, exit 0 clean, 1 findings, 2 cannot run."""
import ast
import io
import os
import re
import sys
import tokenize
import unicodedata

CODES = r"[A-Z]+[0-9]+(?:\s*,\s*[A-Z]+[0-9]+)*"
NAMES = r"[\w-]+(?:\s*,\s*[\w-]+)*"
DASH = r"(?:\s+--\s+(?P<reason>\S.*))"
HASH = r"(?:\s+#\s*(?P<reason>\S.*))"
DIRECTIVES = [
    re.compile(r"^noqa:\s*" + CODES + DASH + "$"),
    re.compile(r"^ruff:\s*noqa:\s*" + CODES + DASH + "$"),
    re.compile(r"^type:\s*ignore\[[\w,\s-]+\]" + HASH + "$"),
    re.compile(r"^pyright:\s*ignore\[[\w,\s-]+\]" + HASH + "$"),
    re.compile(r"^pyright:\s*(?:basic|strict|standard|report\w+\s*=\s*\w+(?:\s*,\s*report\w+\s*=\s*\w+)*)$"),
    re.compile(r"^mypy:\s*[\w-]+(?:\s*=\s*[\w.-]+)?(?:\s*,\s*[\w-]+(?:\s*=\s*[\w.-]+)?)*$"),
    re.compile(r"^pylint:\s*(?:disable|disable-next|disable-all|skip-file)(?:\s*=\s*" + NAMES + r")?" + DASH + "$"),
    re.compile(r"^pylint:\s*enable(?:\s*=\s*" + NAMES + r")?$"),
    re.compile(r"^isort:\s*(?:skip_file|skip|off|on|split|dont-add-imports)$"),
    re.compile(r"^fmt:\s*(?:off|on|skip)$"),
    re.compile(r"^nosec(?:\s+B[0-9]+(?:\s*,\s*B[0-9]+)*)?" + DASH + "$"),
    re.compile(r"^pragma:\s*no\s+(?:cover|branch)" + DASH + "$"),
    re.compile(r"^NOSONAR(?:\s*\([\w:,\s.-]*\))?" + DASH + "$"),
    re.compile(r"^gitleaks:allow" + DASH + "$"),
    re.compile(r"^-\*-\s*coding:\s*[-\w.]+\s*-\*-$"),
    re.compile(r"^coding[:=]\s*[-\w.]+$"),
    re.compile(r"^!\s*/\S*(?:\s+\S+)*$"),
]
SUPPRESSORS = [
    (re.compile(r"^noqa\b"), "# noqa: CODE -- reason"),
    (re.compile(r"^ruff:\s*noqa\b"), "# ruff: noqa: CODE -- reason"),
    (re.compile(r"^type:\s*ignore\b"), "# type: ignore[code]  # reason"),
    (re.compile(r"^pyright:\s*ignore\b"), "# pyright: ignore[rule]  # reason"),
    (re.compile(r"^pylint:\s*disable"), "# pylint: disable=name -- reason"),
    (re.compile(r"^nosec\b"), "# nosec B101 -- reason"),
    (re.compile(r"^pragma:\s*no\s+(?:cover|branch)\b"), "# pragma: no cover -- reason"),
    (re.compile(r"^NOSONAR\b"), "# NOSONAR -- reason"),
    (re.compile(r"^gitleaks:allow"), "# gitleaks:allow -- reason"),
]
YEAR = r"[0-9]{4}(?:[ \t]*[-\u2013][ \t]*(?:[0-9]{4}|present))?"
YEARS = YEAR + r"(?:[ \t]*,[ \t]*" + YEAR + r")*"
COPYRIGHT = re.compile(r"(?:copyright(?:[ \t]*(?:\(c\)|\u00a9))?|\(c\)|\u00a9)[ \t]*" + YEARS + r",?(?:[ \t]+(.*))?", re.I | re.A)
RESERVED = re.compile(r"[ \t]*all rights reserved\.?[ \t]*$", re.I | re.A)
ALL_RIGHTS = re.compile(r"all rights reserved\.?", re.I | re.A)
HOLDER_PUNCT = ".,&'-"
HOLDER_LINK = re.compile(r"<[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+>|<https?://[A-Za-z0-9._~:/?#@!$&'*+,;=%-]+>|https?://[A-Za-z0-9._~:/?#@!$&'*+,;=%-]+")
LICENCE_REF = re.compile(r"LicenseRef-[A-Za-z0-9.-]+")
SPDX_PREFIX = "SPDX-License-Identifier:"
SPDX_BODY = re.compile(r"(?: *(?:\(|\)|[A-Za-z0-9.+-]+))* *")
SPDX_TOKEN = re.compile(r"\(|\)|[A-Za-z0-9.+-]+")
MAX_COPYRIGHT_CHARS = 100
MAX_HOLDER_TOKENS = 8
MAX_COPYRIGHT_LINES = 3
MAX_SPDX_LINES = 1
MAX_LICENCE_LINES = 40
MIN_LICENCE_WORDS = 4
MAX_TITLE_WORDS = 4
LICENCE_FILE = "check-comments.licences.txt"
FILLER = {"todo", "fixme", "xxx", "tbd"}
MIN_REASON_WORDS = 3
ASIDE = re.compile(r"(^|\s)\([^()]*\S[^()]*\)")
ENTRY = re.compile(r"^\*{0,2}(\w[\w.]*)(?:\s*\([^)]*\))?\s*:\s*\S")
FIELD = re.compile(r"^:(\w+)(?:\s+([^:]+?))?:(?:\s|$)")
FIELD_PARAM = {"param", "parameter", "arg", "argument", "key", "keyword", "type"}
FIELD_ATTR = {"ivar", "cvar", "var", "vartype"}
FIELD_RAISE = {"raises", "raise", "except", "exception"}
FIELD_RETURN = {"returns", "return", "rtype", "yields", "yield", "ytype"}
SECTION_KIND = {
    "args": "params", "arguments": "params", "parameters": "params", "other parameters": "params", "keyword args": "params",
    "attributes": "attrs", "raises": "raises", "return": "rets", "returns": "rets", "yield": "rets", "yields": "rets",
}
MAX_CONTINUATION = 2
MAX_ENTRY_WORDS = 12
PROPERTY_DECORATORS = {"property", "cached_property", "setter", "getter", "deleter"}
SECTION = re.compile(r"^(Args|Arguments|Parameters|Other Parameters|Keyword Args|Returns?|Yields?|Raises?|Attributes|Examples?|Notes?|See Also|References|Warns|Warnings|Todo):\s*$")
SKIP_TOKENS = (tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.ENCODING, tokenize.ENDMARKER, tokenize.COMMENT)
VERSION = sys.version.split()[0]
LICENCES = []
LICENCE_IDS = set()
EXCEPTION_IDS = set()


def die(msg):
    sys.stderr.write("check-comments: %s\n" % msg)
    sys.exit(2)


def parse_args(argv):
    opt = {"max": 0, "max_line": 0, "max_reason": 0, "adr": False}
    names = {"--max": "max", "--max-line": "max_line", "--max-reason": "max_reason"}
    i = 0
    while i < len(argv):
        if argv[i] in names:
            i += 1
            opt[names[argv[i - 1]]] = int(argv[i])
        elif argv[i] == "--adr":
            opt["adr"] = True
        i += 1
    if min(opt["max"], opt["max_line"], opt["max_reason"]) < 1:
        die("internal: --max, --max-line and --max-reason must be positive numbers")
    return opt


def changed_set(spec):
    if spec == "all":
        return None
    out = set()
    for r in spec.split(","):
        a, b = r.split("-")
        out.update(range(int(a), int(b) + 1))
    return out


def weak_reason(reason):
    words = [w for w in re.findall(r"[\w'-]+", reason) if w.lower() not in FILLER]
    words = [w for w in words if len(w) >= 2 and re.search(r"[^\W\d_]", w)]
    return len(words) < MIN_REASON_WORDS or len({w.lower() for w in words}) < 2


def suppressor_form(text):
    for rx, form in SUPPRESSORS:
        if rx.match(text):
            return form
    return ""


def directive_of(text):
    """Returns three values: is a directive, its reason, and the expected form when a suppressor is malformed."""
    for rx in DIRECTIVES:
        m = rx.match(text)
        if m:
            reason = m.groupdict().get("reason") or ""
            if "reason" in rx.groupindex and weak_reason(reason):
                return True, "", suppressor_form(text)
            return True, reason, ""
    form = suppressor_form(text)
    if form:
        return True, "", form
    return False, "", ""


def header_end(tokens, idx):
    """Returns the line of the colon that ends the def header at tokens[idx], or None."""
    depth = 0
    for t in tokens[idx + 1:]:
        if t.type != tokenize.OP:
            continue
        if t.string in "([{":
            depth += 1
        elif t.string in ")]}":
            depth -= 1
        elif t.string == ":" and depth == 0:
            return t.start[0]
    return None


def header_ends(tokens):
    """Maps the line of each def keyword to the line of the colon that ends its header."""
    ends = {}
    for idx, tok in enumerate(tokens):
        if tok.type == tokenize.NAME and tok.string == "def" and not (idx > 0 and tokens[idx - 1].string == "."):
            end = header_end(tokens, idx)
            if end is not None:
                ends[tok.start[0]] = end
    return ends


def annotation_names(node):
    names = set()
    if node is not None:
        for n in ast.walk(node):
            if isinstance(n, ast.Name):
                names.add(n.id)
            elif isinstance(n, ast.Attribute):
                names.add(n.attr)
            elif isinstance(n, ast.Constant) and isinstance(n.value, str):
                names.update(re.findall(r"\w+", n.value))
    return names


def scope_nodes(node):
    """Yields the nodes of one scope, without descending into a nested function, class or lambda."""
    stack = list(ast.iter_child_nodes(node))
    while stack:
        n = stack.pop()
        yield n
        if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
            stack.extend(ast.iter_child_nodes(n))


def body_after_docstring(fn):
    """Returns the body of a function without its leading docstring."""
    first = fn.body[0] if fn.body else None
    if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
        return fn.body[1:]
    return fn.body


def is_placeholder(stmt):
    """True for pass, `...` and raise NotImplementedError."""
    if isinstance(stmt, ast.Pass):
        return True
    if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant) and stmt.value.value is Ellipsis:
        return True
    exc = stmt.exc.func if isinstance(stmt, ast.Raise) and isinstance(stmt.exc, ast.Call) else getattr(stmt, "exc", None)
    return isinstance(stmt, ast.Raise) and isinstance(exc, ast.Name) and exc.id == "NotImplementedError"


def is_stub(fn):
    """True for an abstract or placeholder body: only a docstring, `...`, pass, or raise NotImplementedError."""
    return all(is_placeholder(stmt) for stmt in body_after_docstring(fn))


def decorator_name(d):
    d = d.func if isinstance(d, ast.Call) else d
    return d.id if isinstance(d, ast.Name) else d.attr if isinstance(d, ast.Attribute) else ""


FUNCTION_NODES = (ast.FunctionDef, ast.AsyncFunctionDef)


def add_args(names, fn):
    """Adds every parameter name of the function."""
    a = fn.args
    for arg in a.posonlyargs + a.args + a.kwonlyargs:
        names["params"].add(arg.arg)
    for arg in (a.vararg, a.kwarg):
        if arg is not None:
            names["params"].add(arg.arg)


def add_target(names, t, plain):
    """Adds a plain name, or a self attribute, assigned by the target."""
    if isinstance(t, ast.Name) and plain:
        names["attrs"].add(t.id)
    elif isinstance(t, ast.Attribute) and isinstance(t.value, ast.Name) and t.value.id == "self" and not plain:
        names["attrs"].add(t.attr)
    elif isinstance(t, (ast.Tuple, ast.List)):
        for e in t.elts:
            add_target(names, e, plain)


def add_assign(names, stmt, plain):
    """Adds the targets of an assignment statement."""
    if isinstance(stmt, ast.Assign):
        for t in stmt.targets:
            add_target(names, t, plain)
    elif isinstance(stmt, (ast.AnnAssign, ast.AugAssign)):
        add_target(names, stmt.target, plain)


def raised_name(exc_node):
    """Returns the name of the raised exception, or None for any other expression."""
    exc = exc_node.func if isinstance(exc_node, ast.Call) else exc_node
    if isinstance(exc, ast.Name):
        return exc.id
    return exc.attr if isinstance(exc, ast.Attribute) else None


def gives_value(n):
    """True for a return with a value other than None, and for a yield."""
    if isinstance(n, ast.Return):
        return n.value is not None and not (isinstance(n.value, ast.Constant) and n.value.value is None)
    return isinstance(n, (ast.Yield, ast.YieldFrom))


def add_scope(names, scope, self_attrs):
    """Adds raised names and value flags of one scope, and self attributes when asked."""
    for n in scope_nodes(scope):
        if isinstance(n, ast.Raise) and n.exc is not None:
            raised = raised_name(n.exc)
            if raised is not None:
                names["raises"].add(raised)
        elif gives_value(n):
            names["value"] = True
        elif self_attrs:
            add_assign(names, n, False)


def add_method(names, stmt):
    """Adds the property name and scope of a method; returns True for __init__."""
    is_init = stmt.name == "__init__"
    if is_init:
        add_args(names, stmt)
    if any(decorator_name(d) in PROPERTY_DECORATORS for d in stmt.decorator_list):
        names["attrs"].add(stmt.name)
    add_scope(names, stmt, True)
    return is_init


def add_class(names, node):
    """Adds the class body names, its methods and the dataclass-style fields."""
    has_init = False
    fields = set()
    for stmt in node.body:
        add_assign(names, stmt, True)
        if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
            fields.add(stmt.target.id)
        if isinstance(stmt, FUNCTION_NODES) and add_method(names, stmt):
            has_init = True
    if not has_init:
        names["params"].update(fields)
    names["value"] = False


def documented_names(node):
    """Collects what a docstring may list: a function signature, a class body and its self attributes, module-level assignments, raised names and return types."""
    names = {"params": set(), "attrs": set(), "raises": set(), "rets": set(), "value": False}
    if isinstance(node, FUNCTION_NODES):
        add_args(names, node)
        names["rets"] = annotation_names(node.returns)
        add_scope(names, node, False)
        if is_stub(node):
            names["value"] = True
    elif isinstance(node, ast.ClassDef):
        add_class(names, node)
    else:
        for stmt in node.body:
            add_assign(names, stmt, True)
        add_scope(names, node, False)
        names["value"] = False
    return names


def doc_line_text(raw, idx, last):
    """Returns a docstring line without its quotes and surrounding space."""
    t = raw.strip()
    if idx == 0:
        t = re.sub(r"^[rRuUbB]*(\"\"\"|''')", "", t)
    if idx == last:
        t = re.sub(r"(\"\"\"|''')$", "", t).strip()
    return t


def is_continuation(idx, entry_indent, indent, cont, t, max_line):
    """True for a short indented line that continues the entry above it."""
    return idx > 0 and entry_indent is not None and indent > entry_indent and cont < MAX_CONTINUATION and len(t) <= max_line


def docstring_prose(source_lines, node, max_line):
    """Counts the prose lines of a docstring. An entry line is left out only when it names a parameter, attribute, raised exception or return of the documented code."""
    doc = node.body[0]
    lines = source_lines[doc.lineno - 1:doc.end_lineno]
    known = documented_names(node)
    seen = set()
    count = 0
    section = None
    entry_indent = None
    cont = 0
    for idx, raw in enumerate(lines):
        t = doc_line_text(raw, idx, len(lines) - 1)
        indent = len(raw) - len(raw.lstrip())
        if t == "":
            section = None
            entry_indent = None
            continue
        head = SECTION.match(t)
        if head:
            section = SECTION_KIND.get(head.group(1).lower(), "other")
            entry_indent = None
            continue
        if is_continuation(idx, entry_indent, indent, cont, t, max_line):
            cont += 1
            continue
        if idx > 0 and len(t) <= max_line and is_entry(t, section, known, seen):
            entry_indent = indent
            cont = 0
            continue
        entry_indent = None
        count += 1
    return count


def field_pool(kind, known):
    """Returns the names a Sphinx field kind may document, or None for an unknown kind."""
    if kind in FIELD_RETURN:
        return {""} if known["rets"] or known["value"] else set()
    if kind in FIELD_PARAM:
        return known["params"]
    if kind in FIELD_ATTR:
        return known["attrs"] | known["params"]
    if kind in FIELD_RAISE:
        return known["raises"]
    return None


def field_entry(f, known, seen):
    """True for a Sphinx field line that names a real name of the documented code, once per name."""
    kind, arg = f.group(1), (f.group(2) or "").strip()
    pool = field_pool(kind, known)
    if pool is None:
        return False
    name = "" if kind in FIELD_RETURN else (arg.split()[-1] if arg else "")
    key = (kind, name)
    if name not in pool or key in seen:
        return False
    seen.add(key)
    return True


def bare_entry(t, section, known, seen):
    """True for a short line in a Returns or Raises section when the code has something to document."""
    if section not in ("rets", "raises") or len(t.split()) > MAX_ENTRY_WORDS or (section, "") in seen:
        return False
    has_source = (known["rets"] or known["value"]) if section == "rets" else known["raises"]
    if has_source:
        seen.add((section, ""))
        return True
    return False


def named_entry(m, section, known, seen):
    """True for a section line whose leading name is a real name of the documented code, once per name."""
    name = m.group(1).split(".")[-1]
    key = (section, name)
    if key in seen:
        return False
    if section == "rets":
        ok = name in known["rets"] if known["rets"] else known["value"] and not any(k[0] == "rets" for k in seen)
    else:
        ok = name in known[section]
    if ok:
        seen.add(key)
    return ok


def is_entry(t, section, known, seen):
    """True when the line is a section entry or Sphinx field for a real name of the documented code, once per name."""
    f = FIELD.match(t)
    if f:
        return field_entry(f, known, seen)
    m = ENTRY.match(t)
    if m is None:
        return bare_entry(t, section, known, seen)
    if section in (None, "other"):
        return False
    return named_entry(m, section, known, seen)


class Scope:
    """One file under check: its name, limits, report callback, changed lines and the code layout the placement rules need."""

    def __init__(self, rel, opt, report, changed):
        self.rel = rel
        self.opt = opt
        self.report = report
        self.changed = changed
        self.funcs = []
        self.starts = set()
        self.code_lines = []

    def touches(self, a, b):
        """True when the whole file is checked or a line in a to b changed."""
        return self.changed is None or any(n in self.changed for n in range(a, b + 1))

    def flag(self, line, rule, msg):
        """Reports one finding of this file."""
        self.report(self.rel, line, rule, msg)

    def adr(self):
        """Returns the ADR hint when --adr is on."""
        return " Cite the ADR by number (for example ADR-0007) instead of restating it." if self.opt["adr"] else ""


def read_source(rel):
    """Returns the decoded file text, or stops with exit 2 when it cannot be read."""
    try:
        with open(rel, "rb") as fh:
            raw = fh.read()
        return raw.decode("utf-8-sig")
    except (OSError, UnicodeDecodeError) as exc:
        die("cannot read %s: %s" % (rel, exc))


def parse_source(rel, source, report):
    """Returns the tree and tokens, or None after reporting a file that does not parse."""
    try:
        tree = ast.parse(source, rel)
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (SyntaxError, tokenize.TokenError, IndentationError, ValueError) as exc:
        report(rel, getattr(exc, "lineno", None) or 1, "comments/parse", "file does not parse with Python %s (%s), so its comments cannot be judged. Fix: repair the syntax error, or run the gate with a Python release that supports the syntax used." % (VERSION, exc))
        return None
    return tree, tokens


def code_positions(tokens):
    """Returns the first code line and a map of each code line to the column of its first token."""
    first_code = None
    code_start_by_line = {}
    for tok in tokens:
        if tok.type in SKIP_TOKENS:
            continue
        if first_code is None:
            first_code = tok.start[0]
        code_start_by_line.setdefault(tok.start[0], tok.start[1])
    return first_code, code_start_by_line


def node_starts(node, match_case):
    """Returns the lines where a node begins a statement, decorator, argument, element or entry."""
    lines = set()
    if isinstance(node, (ast.stmt, ast.ExceptHandler)):
        lines.add(node.lineno)
        lines.update(d.lineno for d in getattr(node, "decorator_list", []))
    if isinstance(node, ast.arg):
        lines.add(node.lineno)
    elif isinstance(node, (ast.List, ast.Tuple, ast.Set)):
        lines.update(e.lineno for e in node.elts)
    elif isinstance(node, ast.Call):
        lines.update(a.lineno for a in node.args)
        lines.update(getattr(kw, "lineno", kw.value.lineno) for kw in node.keywords)
    elif isinstance(node, ast.Dict):
        lines.update((k if k is not None else v).lineno for k, v in zip(node.keys, node.values))
    elif match_case is not None and isinstance(node, match_case):
        lines.add(node.pattern.lineno)
    return lines


def node_func(node, hends):
    """Returns the header line, end line and column of a function or lambda, else None."""
    if isinstance(node, FUNCTION_NODES):
        return (hends.get(node.lineno, node.lineno), node.end_lineno, node.col_offset)
    if isinstance(node, ast.Lambda):
        return (node.lineno, node.end_lineno, node.col_offset)
    return None


def has_docstring(node):
    """True for a module, function or class whose first statement is a string."""
    if not isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) or not node.body:
        return False
    first = node.body[0]
    return isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str)


def check_docstring(node, source_lines, sc):
    """Reports a docstring with more prose lines than the limit."""
    first = node.body[0]
    count = docstring_prose(source_lines, node, sc.opt["max_line"])
    if count > sc.opt["max"] and sc.touches(first.lineno, first.end_lineno):
        sc.flag(first.lineno, "comments/length", "docstring is %d prose lines, limit %d. Fix: cut it to %d lines or fewer, section entries such as Args do not count.%s" % (count, sc.opt["max"], sc.opt["max"], sc.adr()))


def scan_tree(tree, tokens, source_lines, sc):
    """Fills the function spans and statement start lines of the scope, and checks each docstring."""
    hends = header_ends(tokens)
    match_case = getattr(ast, "match_case", None)
    for node in ast.walk(tree):
        sc.starts |= node_starts(node, match_case)
        span = node_func(node, hends)
        if span is not None:
            sc.funcs.append(span)
        if has_docstring(node):
            check_docstring(node, source_lines, sc)


def keyword_starts(tokens, code_start_by_line):
    """Returns the lines that begin with else, finally or if."""
    return {tok.start[0] for tok in tokens if tok.type == tokenize.NAME and tok.string in ("else", "finally", "if") and code_start_by_line.get(tok.start[0]) == tok.start[1]}


def comment_items(tokens, code_start_by_line, first_code):
    """Returns one record per comment token."""
    items = []
    for tok in tokens:
        if tok.type != tokenize.COMMENT:
            continue
        line, col = tok.start
        text = tok.string[1:].strip()
        before = code_start_by_line.get(line)
        trailing = before is not None and before < col
        is_dir, reason, bad = directive_of(text)
        items.append({"line": line, "col": col, "text": text, "trailing": trailing, "directive": is_dir, "reason": reason, "bad": bad, "top": first_code is None or line < first_code})
    return items


def check_item(it, sc):
    """Reports the directive, trailing and reason findings of one comment."""
    if not sc.touches(it["line"], it["line"]):
        return
    if it["bad"]:
        sc.flag(it["line"], "comments/directive", "directive without a reason or in the wrong form. Fix: write it as `%s`, with a one-line reason of at least three words that is not only TODO." % it["bad"])
    if it["trailing"] and not it["directive"]:
        sc.flag(it["line"], "comments/trailing", "comment shares a line with code. Fix: move it on its own line directly above the statement or declaration it explains, or delete it.")
    if it["directive"] and it["reason"]:
        check_reason(it, sc)


def check_reason(it, sc):
    """Reports a directive reason that is too long or has an aside."""
    if len(it["reason"]) > sc.opt["max_reason"]:
        sc.flag(it["line"], "comments/length", "directive reason is %d characters, limit %d. Fix: shorten the reason, or delete it." % (len(it["reason"]), sc.opt["max_reason"]))
    if ASIDE.search(it["reason"]):
        sc.flag(it["line"], "comments/aside", "parenthetical aside in a directive reason. Fix: make it a plain phrase, or delete it.")


def split_chains(own):
    """Groups comments on consecutive lines into chains."""
    chains = []
    k = 0
    while k < len(own):
        j = k
        while j + 1 < len(own) and own[j + 1]["line"] == own[j]["line"] + 1:
            j += 1
        chains.append(own[k:j + 1])
        k = j + 1
    return chains


def check_long_lines(chain, exempt, sc):
    """Reports each comment line longer than the limit, except the exempt ones."""
    for it in chain:
        if len(it["text"]) > sc.opt["max_line"] and it not in exempt and sc.touches(it["line"], it["line"]):
            sc.flag(it["line"], "comments/length", "comment line is %d characters, limit %d. Fix: cut it or split it into shorter sentences." % (len(it["text"]), sc.opt["max_line"]))


def in_function(first, sc):
    """True when the comment sits inside a function body or trails it."""
    for hend, end, col in sc.funcs:
        if first["line"] > hend and (first["line"] <= end or (first["col"] > col and no_code_between(sc.code_lines, end, first["line"]))):
            return True
    return False


def check_placement(chain, prose, sc):
    """Reports a comment that is inside a function or not directly above a statement."""
    first = prose[0]
    if in_function(first, sc):
        sc.flag(first["line"], "comments/placement", "comment inside a function body. Fix: delete it, or move the note on its own line directly above the function.")
    elif not first["top"]:
        nxt = next_code_line(sc.code_lines, chain[-1]["line"])
        if nxt != chain[-1]["line"] + 1 or nxt not in sc.starts:
            sc.flag(first["line"], "comments/placement", "comment is not on its own line at the top of the file or directly above a statement, declaration or dict entry. Fix: move it there, or delete it.")


def check_prose(prose, prose_changed, sc):
    """Reports a bracketed comment, or the parenthetical asides of the prose lines."""
    if not prose:
        return
    joined = "\n".join(it["text"] for it in prose).strip()
    if prose_changed and re.match(r"^[(\[{]", joined) and re.search(r"[)\]}]$", joined):
        sc.flag(prose[0]["line"], "comments/bracketed", "comment is wholly in brackets. Fix: write it as a plain sentence without brackets.")
        return
    whole = "\n".join(it["text"] for it in prose)
    for m in ASIDE.finditer(whole):
        before = whole[: m.start() + len(m.group(1))]
        ln = prose[before.count("\n")]["line"]
        if sc.touches(ln, ln):
            sc.flag(ln, "comments/aside", "parenthetical aside in a comment. Fix: make it a plain sentence, or delete it.")


def check_chain(chain, prose, counted, exempt, sc):
    """Checks the placement, size and wording of one comment chain."""
    prose_changed = any(sc.touches(it["line"], it["line"]) for it in prose)
    if prose_changed:
        check_placement(chain, prose, sc)
    size = len([it for it in counted if it["text"] and it not in exempt])
    if size > sc.opt["max"] and any(sc.touches(it["line"], it["line"]) for it in counted):
        sc.flag(counted[0]["line"], "comments/length", "comment block is %d lines, limit %d. Fix: cut it to %d lines or fewer.%s" % (size, sc.opt["max"], sc.opt["max"], sc.adr()))
    kept = [it for it in prose if it not in exempt]
    check_prose(kept, prose_changed, sc)


def check_chains(own, sc):
    """Checks every comment chain and returns the totals of the chains above the first code."""
    used = {"copyright": 0, "spdx": 0, "licence": 0, "open": True}
    top = {"chains": 0, "total": 0, "line": None, "changed": False}
    for chain in split_chains(own):
        prose = [it for it in chain if not it["directive"]]
        counted = [it for it in chain if not it["directive"] or it["reason"]]
        is_top = bool(prose) and prose[0]["top"]
        exempt = licence_items(prose, used) if is_top else []
        check_long_lines(chain, exempt, sc)
        if not counted:
            continue
        if is_top:
            if all(it in exempt or not it["text"] for it in counted):
                continue
            add_top(top, counted, exempt, sc)
        check_chain(chain, prose, counted, exempt, sc)
    return top


def add_top(top, counted, exempt, sc):
    """Adds a chain above the first code to the totals."""
    top["chains"] += 1
    top["total"] += len([it for it in counted if it["text"] and it not in exempt])
    if top["line"] is None:
        top["line"] = counted[0]["line"]
    top["changed"] = top["changed"] or any(sc.touches(it["line"], it["line"]) for it in counted)


def check_file(rel, spec, opt, report):
    source = read_source(rel)
    parsed = parse_source(rel, source, report)
    if parsed is None:
        return
    tree, tokens = parsed
    sc = Scope(rel, opt, report, changed_set(spec))
    first_code, code_start_by_line = code_positions(tokens)
    sc.code_lines = sorted(code_start_by_line)
    scan_tree(tree, tokens, source.splitlines(), sc)
    sc.starts |= keyword_starts(tokens, code_start_by_line)
    items = comment_items(tokens, code_start_by_line, first_code)
    for it in items:
        check_item(it, sc)
    top = check_chains([it for it in items if not it["trailing"]], sc)
    report_top(rel, opt, report, top["chains"], top["total"], top["line"], top["changed"])


def norm_words(text):
    """Lowercase words of a comment line: punctuation, comment markers and list numbers are dropped."""
    return re.findall(r"[^\W_]+", re.sub(r"(?:^|\s)(?:\d+[.)]|[-*•])(?=\s|$)", " ", text.lower()))


def split_licence_data(raw):
    """Returns the licence blocks of the data file as lists of word lists, and fills the id sets."""
    texts = []
    for line in raw.split("\n"):
        if line.startswith("@@ "):
            texts.append([])
        elif texts:
            texts[-1].append(norm_words(line))
        elif line.startswith("licence-ids:"):
            LICENCE_IDS.update(line.split(":", 1)[1].split())
        elif line.startswith("exception-ids:"):
            EXCEPTION_IDS.update(line.split(":", 1)[1].split())
    return texts


def licence_strings(texts):
    """Returns the space-padded word strings of each licence, and of its body when the first line is a title."""
    out = []
    for lines in texts:
        lines = [w for w in lines if w]
        if lines:
            out.append(" " + " ".join(w for ln in lines for w in ln) + " ")
            if len(lines[0]) <= MAX_TITLE_WORDS and len(lines) > 1:
                out.append(" " + " ".join(w for ln in lines[1:] for w in ln) + " ")
    return out


def load_licences():
    """Reads the bundled licence texts as space-padded word strings, one per licence."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), LICENCE_FILE)
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        die("cannot read the bundled licence texts %s: %s. Fix: restore the file next to this script." % (LICENCE_FILE, exc))
    out = licence_strings(split_licence_data(raw))
    if not out:
        die("the bundled licence texts %s hold no licence. Fix: restore the file next to this script." % LICENCE_FILE)
    if not LICENCE_IDS or not EXCEPTION_IDS:
        die("the bundled licence texts %s hold no licence ids or no exception ids. Fix: restore the file next to this script." % LICENCE_FILE)
    return out


class SpdxParser:
    """Reads an SPDX expression over a token list: every id is listed once and nothing is left over."""

    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0
        self.seen = set()

    def peek(self):
        """Returns the next token, or None at the end."""
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def group(self):
        """Reads the rest of a bracketed expression."""
        if not self.expr() or self.peek() != ")":
            return False
        self.pos += 1
        return True

    def exception(self):
        """Reads the exception id after WITH."""
        self.pos += 1
        exc = self.peek()
        if exc not in EXCEPTION_IDS or exc in self.seen:
            return False
        self.seen.add(exc)
        self.pos += 1
        return True

    def licence(self, tok):
        """Reads a licence id, with an optional trailing plus and an optional WITH exception."""
        base = tok[:-1] if tok.endswith("+") else tok
        if (base not in LICENCE_IDS and LICENCE_REF.fullmatch(base) is None) or base in self.seen:
            return False
        self.seen.add(base)
        return self.exception() if self.peek() == "WITH" else True

    def term(self):
        """Reads a licence term or a bracketed expression."""
        tok = self.peek()
        if tok is None:
            return False
        self.pos += 1
        return self.group() if tok == "(" else self.licence(tok)

    def expr(self):
        """Reads terms joined by AND or OR."""
        if not self.term():
            return False
        while self.peek() in ("AND", "OR"):
            self.pos += 1
            if not self.term():
                return False
        return True


def spdx_parse(tokens):
    """True when the tokens are expr := term ((AND|OR) term)*, term := id [WITH exception] or a bracketed expr, every id is listed once, and nothing is left over."""
    parser = SpdxParser(tokens)
    return parser.expr() and parser.pos == len(tokens)


def spdx_ok(text):
    """True for SPDX-License-Identifier: and one expression over the closed id lists in the licence data file."""
    if not text.startswith(SPDX_PREFIX):
        return False
    body = text[len(SPDX_PREFIX):]
    return SPDX_BODY.fullmatch(body) is not None and spdx_parse(SPDX_TOKEN.findall(body))


def holder_ok(rest):
    """True for a holder of at most MAX_HOLDER_TOKENS tokens: letters of any script, digits and . , & ' - only, plus one email or URL token."""
    tokens = [t for t in re.split(r"[ \t]+", rest.strip(" \t")) if t]
    if len(tokens) > MAX_HOLDER_TOKENS or sum(1 for t in tokens if HOLDER_LINK.fullmatch(t)) > 1:
        return False
    for tok in tokens:
        if HOLDER_LINK.fullmatch(tok):
            continue
        for ch in tok:
            if ch not in HOLDER_PUNCT and not ("0" <= ch <= "9") and unicodedata.category(ch)[0] not in "LM":
                return False
    return True


def is_copyright(text):
    """Returns "spdx" for an SPDX line, "copy" for a short Copyright line with a year and a plain holder or an All rights reserved line, else None."""
    if len(text) > MAX_COPYRIGHT_CHARS:
        return None
    if spdx_ok(text):
        return "spdx"
    if ALL_RIGHTS.fullmatch(text):
        return "copy"
    m = COPYRIGHT.fullmatch(text)
    if m is None:
        return None
    return "copy" if holder_ok(RESERVED.sub("", m.group(1) or "")) else None


def licence_items(prose, used):
    """Returns the header lines left uncounted: copyright and SPDX lines, and the lines of a comment that quotes one bundled licence text from its start. Only the comments at the very top qualify, so nothing later is exempt."""
    out = [it for it in prose if not it["text"]]
    if not used["open"]:
        return out
    kinds = [(it, is_copyright(it["text"]) if it["text"] else None) for it in prose]
    copy = [it for it, k in kinds if k == "copy"]
    spdx = [it for it, k in kinds if k == "spdx"]
    rest = [it for it, k in kinds if it["text"] and k is None]
    within = used["copyright"] + len(copy) <= MAX_COPYRIGHT_LINES and used["spdx"] + len(spdx) <= MAX_SPDX_LINES
    if within:
        out += copy + spdx
        used["copyright"] += len(copy)
        used["spdx"] += len(spdx)
    used["open"] = within and not rest
    words = [norm_words(it["text"]) for it in rest]
    matchable = [it for it, w in zip(rest, words) if w]
    found = [w for ws in words for w in ws]
    if matchable and used["licence"] + len(matchable) <= MAX_LICENCE_LINES and len(found) >= MIN_LICENCE_WORDS:
        prefix = " " + " ".join(found) + " "
        if any(lic.startswith(prefix) for lic in LICENCES):
            out += matchable
            used["licence"] += len(matchable)
    return out


def report_top(rel, opt, report, top_chains, top_total, top_line, top_changed):
    if top_chains > 1 and top_total > opt["max"] and top_changed:
        report(rel, top_line, "comments/length", "comments before the first line of code total %d lines, limit %d. Fix: cut them to %d lines or fewer; only a licence header is exempt." % (top_total, opt["max"], opt["max"]))


def next_code_line(sorted_lines, after):
    for ln in sorted_lines:
        if ln > after:
            return ln
    return None


def no_code_between(sorted_lines, end, comment_line):
    """True when no code sits between the function end and the comment, so the comment trails the body."""
    return not any(end < ln < comment_line for ln in sorted_lines)


def main():
    if sys.version_info < (3, 8):
        die("Python %s is too old to read comments (needs 3.8 or newer). Fix: install a newer Python, or create the project .venv with one." % VERSION)
    opt = parse_args(sys.argv[1:])
    LICENCES.extend(load_licences())
    findings = []

    def report(f, l, rule, msg):
        findings.append((f, l, "%s:%d: %s: %s" % (f, l, rule, msg)))

    for spec in sys.stdin.read().split("\n"):
        if not spec:
            continue
        path, _, ranges = spec.rpartition("\t")
        check_file(path, ranges, opt, report)
    for _, _, line in sorted(findings):
        sys.stdout.write(line + "\n")
    sys.exit(1 if findings else 0)


main()

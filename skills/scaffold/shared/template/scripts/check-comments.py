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


def header_ends(tokens):
    """Maps the line of each def keyword to the line of the colon that ends its header."""
    ends = {}
    for idx, tok in enumerate(tokens):
        if tok.type == tokenize.NAME and tok.string == "def" and not (idx > 0 and tokens[idx - 1].string == "."):
            depth = 0
            for t in tokens[idx + 1:]:
                if t.type == tokenize.OP and t.string in "([{":
                    depth += 1
                elif t.type == tokenize.OP and t.string in ")]}":
                    depth -= 1
                elif t.type == tokenize.OP and t.string == ":" and depth == 0:
                    ends[tok.start[0]] = t.start[0]
                    break
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


def is_stub(fn):
    """True for an abstract or placeholder body: only a docstring, `...`, pass, or raise NotImplementedError."""
    for stmt in fn.body[1:] if fn.body and isinstance(fn.body[0], ast.Expr) and isinstance(fn.body[0].value, ast.Constant) and isinstance(fn.body[0].value.value, str) else fn.body:
        if isinstance(stmt, ast.Pass):
            continue
        if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant) and stmt.value.value is Ellipsis:
            continue
        exc = stmt.exc.func if isinstance(stmt, ast.Raise) and isinstance(stmt.exc, ast.Call) else getattr(stmt, "exc", None)
        if isinstance(stmt, ast.Raise) and isinstance(exc, ast.Name) and exc.id == "NotImplementedError":
            continue
        return False
    return True


def decorator_name(d):
    d = d.func if isinstance(d, ast.Call) else d
    return d.id if isinstance(d, ast.Name) else d.attr if isinstance(d, ast.Attribute) else ""


def documented_names(node):
    """Collects what a docstring may list: a function signature, a class body and its self attributes, module-level assignments, raised names and return types."""
    names = {"params": set(), "attrs": set(), "raises": set(), "rets": set(), "value": False}
    fields = set()

    def add_args(fn):
        a = fn.args
        for arg in a.posonlyargs + a.args + a.kwonlyargs:
            names["params"].add(arg.arg)
        for arg in (a.vararg, a.kwarg):
            if arg is not None:
                names["params"].add(arg.arg)

    def add_target(t, plain):
        if isinstance(t, ast.Name) and plain:
            names["attrs"].add(t.id)
        elif isinstance(t, ast.Attribute) and isinstance(t.value, ast.Name) and t.value.id == "self" and not plain:
            names["attrs"].add(t.attr)
        elif isinstance(t, (ast.Tuple, ast.List)):
            for e in t.elts:
                add_target(e, plain)

    def add_assign(stmt, plain):
        if isinstance(stmt, ast.Assign):
            for t in stmt.targets:
                add_target(t, plain)
        elif isinstance(stmt, (ast.AnnAssign, ast.AugAssign)):
            add_target(stmt.target, plain)

    def add_scope(scope, self_attrs):
        for n in scope_nodes(scope):
            if isinstance(n, ast.Raise) and n.exc is not None:
                exc = n.exc.func if isinstance(n.exc, ast.Call) else n.exc
                if isinstance(exc, ast.Name):
                    names["raises"].add(exc.id)
                elif isinstance(exc, ast.Attribute):
                    names["raises"].add(exc.attr)
            elif isinstance(n, ast.Return) and n.value is not None and not (isinstance(n.value, ast.Constant) and n.value.value is None):
                names["value"] = True
            elif isinstance(n, (ast.Yield, ast.YieldFrom)):
                names["value"] = True
            elif self_attrs:
                add_assign(n, False)

    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        add_args(node)
        names["rets"] = annotation_names(node.returns)
        add_scope(node, False)
        if is_stub(node):
            names["value"] = True
    elif isinstance(node, ast.ClassDef):
        has_init = False
        for stmt in node.body:
            add_assign(stmt, True)
            if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
                fields.add(stmt.target.id)
            if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if stmt.name == "__init__":
                    has_init = True
                    add_args(stmt)
                if any(decorator_name(d) in PROPERTY_DECORATORS for d in stmt.decorator_list):
                    names["attrs"].add(stmt.name)
                add_scope(stmt, True)
        if not has_init:
            names["params"].update(fields)
        names["value"] = False
    else:
        for stmt in node.body:
            add_assign(stmt, True)
        add_scope(node, False)
        names["value"] = False
    return names


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
        t = raw.strip()
        indent = len(raw) - len(raw.lstrip())
        if idx == 0:
            t = re.sub(r"^[rRuUbB]*(\"\"\"|''')", "", t)
        if idx == len(lines) - 1:
            t = re.sub(r"(\"\"\"|''')$", "", t).strip()
        if t == "":
            section = None
            entry_indent = None
            continue
        head = SECTION.match(t)
        if head:
            section = SECTION_KIND.get(head.group(1).lower(), "other")
            entry_indent = None
            continue
        if idx > 0 and entry_indent is not None and indent > entry_indent and cont < MAX_CONTINUATION and len(t) <= max_line:
            cont += 1
            continue
        if idx > 0 and len(t) <= max_line and is_entry(t, section, known, seen):
            entry_indent = indent
            cont = 0
            continue
        entry_indent = None
        count += 1
    return count


def is_entry(t, section, known, seen):
    """True when the line is a section entry or Sphinx field for a real name of the documented code, once per name."""
    f = FIELD.match(t)
    if f:
        kind, arg = f.group(1), (f.group(2) or "").strip()
        name = arg.split()[-1] if arg else ""
        if kind in FIELD_RETURN:
            pool, name = ({""} if known["rets"] or known["value"] else set()), ""
        elif kind in FIELD_PARAM:
            pool = known["params"]
        elif kind in FIELD_ATTR:
            pool = known["attrs"] | known["params"]
        elif kind in FIELD_RAISE:
            pool = known["raises"]
        else:
            return False
        key = (kind, name)
        if name not in pool or key in seen:
            return False
        seen.add(key)
        return True
    m = ENTRY.match(t)
    if m is None and section in ("rets", "raises") and len(t.split()) <= MAX_ENTRY_WORDS and (section, "") not in seen:
        has_source = (known["rets"] or known["value"]) if section == "rets" else known["raises"]
        if has_source:
            seen.add((section, ""))
            return True
    if m is None or section in (None, "other"):
        return False
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


def check_file(rel, spec, opt, report):
    try:
        with open(rel, "rb") as fh:
            raw = fh.read()
        source = raw.decode("utf-8-sig")
    except (OSError, UnicodeDecodeError) as exc:
        die("cannot read %s: %s" % (rel, exc))
    try:
        tree = ast.parse(source, rel)
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (SyntaxError, tokenize.TokenError, IndentationError, ValueError) as exc:
        report(rel, getattr(exc, "lineno", None) or 1, "comments/parse", "file does not parse with Python %s (%s), so its comments cannot be judged. Fix: repair the syntax error, or run the gate with a Python release that supports the syntax used." % (VERSION, exc))
        return
    changed = changed_set(spec)

    def touches(a, b):
        return changed is None or any(l in changed for l in range(a, b + 1))

    first_code = None
    code_start_by_line = {}
    for tok in tokens:
        if tok.type in SKIP_TOKENS:
            continue
        if first_code is None:
            first_code = tok.start[0]
        code_start_by_line.setdefault(tok.start[0], tok.start[1])
    sorted_code_lines = sorted(code_start_by_line)

    funcs = []
    starts = set()
    hends = header_ends(tokens)
    match_case = getattr(ast, "match_case", None)
    source_lines = source.splitlines()
    for node in ast.walk(tree):
        if isinstance(node, ast.stmt) or isinstance(node, ast.ExceptHandler):
            starts.add(node.lineno)
            for d in getattr(node, "decorator_list", []):
                starts.add(d.lineno)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            funcs.append((hends.get(node.lineno, node.lineno), node.end_lineno, node.col_offset))
        elif isinstance(node, ast.Lambda):
            funcs.append((node.lineno, node.end_lineno, node.col_offset))
        elif isinstance(node, ast.arg):
            starts.add(node.lineno)
        elif isinstance(node, (ast.List, ast.Tuple, ast.Set)):
            for e in node.elts:
                starts.add(e.lineno)
        elif isinstance(node, ast.Call):
            for a in node.args:
                starts.add(a.lineno)
            for kw in node.keywords:
                starts.add(getattr(kw, "lineno", kw.value.lineno))
        elif isinstance(node, ast.Dict):
            for k, v in zip(node.keys, node.values):
                starts.add((k if k is not None else v).lineno)
        elif match_case is not None and isinstance(node, match_case):
            starts.add(node.pattern.lineno)
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                count = docstring_prose(source_lines, node, opt["max_line"])
                if count > opt["max"] and touches(first.lineno, first.end_lineno):
                    adr = " Cite the ADR by number (for example ADR-0007) instead of restating it." if opt["adr"] else ""
                    report(rel, first.lineno, "comments/length", "docstring is %d prose lines, limit %d. Fix: cut it to %d lines or fewer, section entries such as Args do not count.%s" % (count, opt["max"], opt["max"], adr))

    for idx, tok in enumerate(tokens):
        if tok.type == tokenize.NAME and tok.string in ("else", "finally", "if") and code_start_by_line.get(tok.start[0]) == tok.start[1]:
            starts.add(tok.start[0])

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

    for it in items:
        if it["bad"] and touches(it["line"], it["line"]):
            report(rel, it["line"], "comments/directive", "directive without a reason or in the wrong form. Fix: write it as `%s`, with a one-line reason of at least three words that is not only TODO." % it["bad"])
        if it["trailing"] and not it["directive"] and touches(it["line"], it["line"]):
            report(rel, it["line"], "comments/trailing", "comment shares a line with code. Fix: move it on its own line directly above the statement or declaration it explains, or delete it.")
        if it["directive"] and it["reason"] and touches(it["line"], it["line"]):
            if len(it["reason"]) > opt["max_reason"]:
                report(rel, it["line"], "comments/length", "directive reason is %d characters, limit %d. Fix: shorten the reason, or delete it." % (len(it["reason"]), opt["max_reason"]))
            if ASIDE.search(it["reason"]):
                report(rel, it["line"], "comments/aside", "parenthetical aside in a directive reason. Fix: make it a plain phrase, or delete it.")

    own = [it for it in items if not it["trailing"]]
    k = 0
    used = {"copyright": 0, "spdx": 0, "licence": 0, "open": True}
    top_total = 0
    top_chains = 0
    top_line = None
    top_changed = False
    while k < len(own):
        j = k
        while j + 1 < len(own) and own[j + 1]["line"] == own[j]["line"] + 1:
            j += 1
        chain = own[k:j + 1]
        k = j + 1
        prose = [it for it in chain if not it["directive"]]
        counted = [it for it in chain if not it["directive"] or it["reason"]]
        exempt = licence_items(prose, used) if prose and prose[0]["top"] else []
        for it in chain:
            if len(it["text"]) > opt["max_line"] and it not in exempt and touches(it["line"], it["line"]):
                report(rel, it["line"], "comments/length", "comment line is %d characters, limit %d. Fix: cut it or split it into shorter sentences." % (len(it["text"]), opt["max_line"]))
        if not counted:
            continue
        if prose and prose[0]["top"]:
            if all(it in exempt or not it["text"] for it in counted):
                continue
            top_chains += 1
            top_total += len([it for it in counted if it["text"] and it not in exempt])
            if top_line is None:
                top_line = counted[0]["line"]
            top_changed = top_changed or any(touches(it["line"], it["line"]) for it in counted)
        start = counted[0]["line"]
        prose_changed = any(touches(it["line"], it["line"]) for it in prose)
        any_changed = any(touches(it["line"], it["line"]) for it in counted)
        if prose_changed:
            first = prose[0]
            inside = False
            for hend, end, col in funcs:
                if first["line"] > hend and (first["line"] <= end or (first["col"] > col and no_code_between(sorted_code_lines, end, first["line"]))):
                    inside = True
            if inside:
                report(rel, first["line"], "comments/placement", "comment inside a function body. Fix: delete it, or move the note on its own line directly above the function.")
            elif not first["top"]:
                nxt = next_code_line(sorted_code_lines, chain[-1]["line"])
                if nxt != chain[-1]["line"] + 1 or nxt not in starts:
                    report(rel, first["line"], "comments/placement", "comment is not on its own line at the top of the file or directly above a statement, declaration or dict entry. Fix: move it there, or delete it.")
        size = len([it for it in counted if it["text"] and it not in exempt])
        if any_changed and size > opt["max"]:
            adr = " Cite the ADR by number (for example ADR-0007) instead of restating it." if opt["adr"] else ""
            report(rel, start, "comments/length", "comment block is %d lines, limit %d. Fix: cut it to %d lines or fewer.%s" % (size, opt["max"], opt["max"], adr))
        prose = [it for it in prose if it not in exempt]
        if not prose:
            continue
        joined = "\n".join(it["text"] for it in prose).strip()
        if prose_changed and re.match(r"^[(\[{]", joined) and re.search(r"[)\]}]$", joined):
            report(rel, prose[0]["line"], "comments/bracketed", "comment is wholly in brackets. Fix: write it as a plain sentence without brackets.")
            continue
        whole = "\n".join(it["text"] for it in prose)
        for m in ASIDE.finditer(whole):
            before = whole[: m.start() + len(m.group(1))]
            ln = prose[before.count("\n")]["line"]
            if touches(ln, ln):
                report(rel, ln, "comments/aside", "parenthetical aside in a comment. Fix: make it a plain sentence, or delete it.")
    report_top(rel, opt, report, top_chains, top_total, top_line, top_changed)


def norm_words(text):
    """Lowercase words of a comment line: punctuation, comment markers and list numbers are dropped."""
    return re.findall(r"[^\W_]+", re.sub(r"(?:^|\s)(?:\d+[.)]|[-*•])(?=\s|$)", " ", text.lower()))


def load_licences():
    """Reads the bundled licence texts as space-padded word strings, one per licence."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), LICENCE_FILE)
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        die("cannot read the bundled licence texts %s: %s. Fix: restore the file next to this script." % (LICENCE_FILE, exc))
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
    out = []
    for lines in texts:
        lines = [w for w in lines if w]
        if lines:
            out.append(" " + " ".join(w for ln in lines for w in ln) + " ")
            if len(lines[0]) <= MAX_TITLE_WORDS and len(lines) > 1:
                out.append(" " + " ".join(w for ln in lines[1:] for w in ln) + " ")
    if not out:
        die("the bundled licence texts %s hold no licence. Fix: restore the file next to this script." % LICENCE_FILE)
    if not LICENCE_IDS or not EXCEPTION_IDS:
        die("the bundled licence texts %s hold no licence ids or no exception ids. Fix: restore the file next to this script." % LICENCE_FILE)
    return out


def spdx_parse(tokens):
    """True when the tokens are expr := term ((AND|OR) term)*, term := id [WITH exception] or a bracketed expr, every id is listed once, and nothing is left over."""
    pos = [0]
    seen = set()

    def peek():
        return tokens[pos[0]] if pos[0] < len(tokens) else None

    def term():
        tok = peek()
        if tok is None:
            return False
        pos[0] += 1
        if tok == "(":
            if not expr() or peek() != ")":
                return False
            pos[0] += 1
            return True
        base = tok[:-1] if tok.endswith("+") else tok
        if (base not in LICENCE_IDS and LICENCE_REF.fullmatch(base) is None) or base in seen:
            return False
        seen.add(base)
        if peek() == "WITH":
            pos[0] += 1
            exc = peek()
            if exc not in EXCEPTION_IDS or exc in seen:
                return False
            seen.add(exc)
            pos[0] += 1
        return True

    def expr():
        if not term():
            return False
        while peek() in ("AND", "OR"):
            pos[0] += 1
            if not term():
                return False
        return True

    return expr() and pos[0] == len(tokens)


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

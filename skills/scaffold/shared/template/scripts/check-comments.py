"""Python reader for check-comments.sh: path and ranges on stdin, one finding per line, exit 0 clean, 1 findings, 2 cannot run."""
import ast
import io
import re
import sys
import tokenize

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
LICENCE = re.compile(r"^(?:\(c\)\s*|©\s*)?(?:Copyright|SPDX-License-Identifier)\b", re.I)
LICENCE_LINE = re.compile(r"copyright|spdx-|licen[sc]e|all rights reserved|warrant|redistribut|permission|liabilit|merchantab|obtain a copy|distributed under|without limitation|applicable law|agreed to in writing|\"as is\"|basis|limitations|governing|https?://", re.I)
MAX_LICENCE_LINES = 15
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
SECTION = re.compile(r"^(Args|Arguments|Parameters|Other Parameters|Keyword Args|Returns?|Yields?|Raises?|Attributes|Examples?|Notes?|See Also|References|Warns|Warnings|Todo):\s*$")
SKIP_TOKENS = (tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.ENCODING, tokenize.ENDMARKER, tokenize.COMMENT)
VERSION = sys.version.split()[0]


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
    return len(words) < MIN_REASON_WORDS


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


def documented_names(node):
    """Collects the names a docstring may list as entries: parameters, attributes, raised exceptions and return types."""
    names = {"params": set(), "attrs": set(), "raises": set(), "rets": set()}

    def add_args(fn):
        a = fn.args
        for arg in a.posonlyargs + a.args + a.kwonlyargs:
            names["params"].add(arg.arg)
        for arg in (a.vararg, a.kwarg):
            if arg is not None:
                names["params"].add(arg.arg)

    def add_targets(stmt):
        targets = stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target] if isinstance(stmt, ast.AnnAssign) else []
        for t in targets:
            if isinstance(t, ast.Name):
                names["attrs"].add(t.id)
            elif isinstance(t, ast.Attribute) and isinstance(t.value, ast.Name) and t.value.id == "self":
                names["attrs"].add(t.attr)

    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        add_args(node)
        names["rets"] = annotation_names(node.returns)
    for n in ast.walk(node):
        if isinstance(n, (ast.Assign, ast.AnnAssign)):
            add_targets(n)
        elif isinstance(n, ast.FunctionDef) and isinstance(node, ast.ClassDef) and n.name == "__init__":
            add_args(n)
        elif isinstance(n, ast.Raise) and n.exc is not None:
            exc = n.exc.func if isinstance(n.exc, ast.Call) else n.exc
            if isinstance(exc, ast.Name):
                names["raises"].add(exc.id)
            elif isinstance(exc, ast.Attribute):
                names["raises"].add(exc.attr)
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
            pool, name = known["rets"] | {""}, ""
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
    if m is None or section in (None, "other"):
        return False
    name = m.group(1).split(".")[-1]
    key = (section, name)
    if key in seen:
        return False
    if section == "rets":
        ok = name in known["rets"] if known["rets"] else not any(k[0] == "rets" for k in seen)
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
    seen_top = False
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
        for it in chain:
            if len(it["text"]) > opt["max_line"] and touches(it["line"], it["line"]):
                report(rel, it["line"], "comments/length", "comment line is %d characters, limit %d. Fix: cut it or split it into shorter sentences." % (len(it["text"]), opt["max_line"]))
        prose = [it for it in chain if not it["directive"]]
        counted = [it for it in chain if not it["directive"] or it["reason"]]
        if not counted:
            continue
        exempt = []
        if prose and prose[0]["top"]:
            first_top = not seen_top
            seen_top = True
            if first_top and LICENCE.search(prose[0]["text"]):
                exempt = licence_items(prose)
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


def licence_items(prose):
    """Returns the leading licence lines of a header, at most MAX_LICENCE_LINES of them; the first other line ends the exemption."""
    out = []
    n = 0
    for it in prose:
        if not it["text"]:
            out.append(it)
            continue
        if n >= MAX_LICENCE_LINES or not LICENCE_LINE.search(it["text"]):
            break
        out.append(it)
        n += 1
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

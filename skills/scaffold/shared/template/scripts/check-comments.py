"""Python reader for check-comments.sh: path and ranges on stdin, one finding per line, exit 0 clean, 1 findings, 2 cannot run."""
import ast
import io
import re
import sys
import tokenize

DIRECTIVE_ANYWHERE = re.compile(r"(noqa\b|NOSONAR|type:\s*ignore)")
DIRECTIVE_START = re.compile(r"^(pragma\b|pyright:|ruff:|fmt:|pylint:|isort:|mypy:|-\*-|istanbul\s|c8\s|v8\s|eslint-)")
LICENCE = re.compile(r"(Copyright|SPDX-License-Identifier|Licensed under|MIT License|Permission is hereby|Apache License|All rights reserved)", re.I)
ASIDE = re.compile(r"(^|\s)\([^()]*\S[^()]*\)")
SKIP_TOKENS = (tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.ENCODING, tokenize.ENDMARKER, tokenize.COMMENT)


def die(msg):
    sys.stderr.write("check-comments: %s\n" % msg)
    sys.exit(2)


def parse_args(argv):
    opt = {"max": 0, "adr": False}
    i = 0
    while i < len(argv):
        if argv[i] == "--max":
            i += 1
            opt["max"] = int(argv[i])
        elif argv[i] == "--adr":
            opt["adr"] = True
        i += 1
    if opt["max"] < 1:
        die("internal: --max must be a positive number")
    return opt


def changed_set(spec):
    if spec == "all":
        return None
    out = set()
    for r in spec.split(","):
        a, b = r.split("-")
        out.update(range(int(a), int(b) + 1))
    return out


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


def check_file(rel, spec, opt, report):
    try:
        with open(rel, "rb") as fh:
            raw = fh.read()
        source = raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        die("cannot read %s: %s" % (rel, exc))
    try:
        tree = ast.parse(source, rel)
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (SyntaxError, tokenize.TokenError, IndentationError) as exc:
        report(rel, getattr(exc, "lineno", None) or 1, "comments/parse", "file does not parse (%s), so its comments cannot be judged. Fix: repair the syntax error." % exc)
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
    decl_starts = set()
    hends = header_ends(tokens)

    def walk(node, in_func):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                start = min([child.lineno] + [d.lineno for d in child.decorator_list])
                decl_starts.add(start)
                funcs.append((hends.get(child.lineno, child.lineno), child.end_lineno, child.col_offset))
                walk(child, True)
            elif isinstance(child, ast.ClassDef):
                start = min([child.lineno] + [d.lineno for d in child.decorator_list])
                decl_starts.add(start)
                walk(child, in_func)
            elif isinstance(child, (ast.Assign, ast.AnnAssign)) and not in_func:
                decl_starts.add(child.lineno)
                walk(child, in_func)
            else:
                walk(child, in_func)

    walk(tree, False)

    items = []
    for tok in tokens:
        if tok.type != tokenize.COMMENT:
            continue
        line, col = tok.start
        text = tok.string[1:].strip()
        before = code_start_by_line.get(line)
        trailing = before is not None and before < col
        shebang = line == 1 and tok.string.startswith("#!")
        directive = shebang or bool(DIRECTIVE_ANYWHERE.search(text)) or bool(DIRECTIVE_START.match(text))
        items.append({"line": line, "col": col, "text": text, "trailing": trailing, "directive": directive, "top": first_code is None or line < first_code})

    for it in items:
        if it["trailing"] and not it["directive"] and touches(it["line"], it["line"]):
            report(rel, it["line"], "comments/trailing", "comment shares a line with code. Fix: move it directly above the declaration it explains, or delete it.")

    full = [it for it in items if not it["trailing"]]
    k = 0
    while k < len(full):
        j = k
        while j + 1 < len(full) and full[j + 1]["line"] == full[j]["line"] + 1:
            j += 1
        chain = full[k:j + 1]
        k = j + 1
        judged = [it for it in chain if not it["directive"]]
        if not judged:
            continue
        if judged[0]["top"] and LICENCE.search(judged[0]["text"]):
            continue
        start = judged[0]["line"]
        any_changed = any(touches(it["line"], it["line"]) for it in judged)
        if any_changed:
            first = judged[0]
            inside = False
            for hend, end, col in funcs:
                if first["line"] > hend and (first["line"] <= end or (first["col"] > col and nxt_stmt_after(sorted_code_lines, end, first["line"]))):
                    inside = True
            if inside:
                report(rel, start, "comments/placement", "comment inside a function body. Fix: delete it, or move the note directly above the function.")
            elif not first["top"]:
                nxt = next_code_line(sorted_code_lines, chain[-1]["line"])
                if nxt != chain[-1]["line"] + 1 or nxt not in decl_starts:
                    report(rel, start, "comments/placement", "comment is not at the top of the file or directly above a declaration. Fix: move it directly above the declaration it explains, or delete it.")
            if len(judged) > opt["max"]:
                adr = " Cite the ADR by number (for example ADR-0007) instead of restating it." if opt["adr"] else ""
                report(rel, start, "comments/length", "comment block is %d lines, limit %d. Fix: cut it to %d lines or fewer.%s" % (len(judged), opt["max"], opt["max"], adr))
        joined = "\n".join(it["text"] for it in judged).strip()
        if any_changed and re.match(r"^[(\[{]", joined) and re.search(r"[)\]}]$", joined):
            report(rel, start, "comments/bracketed", "comment is wholly in brackets. Fix: write it as a plain sentence without brackets.")
            continue
        for m in ASIDE.finditer("\n".join(it["text"] for it in judged)):
            before = "\n".join(it["text"] for it in judged)[: m.start() + len(m.group(1))]
            ln = judged[before.count("\n")]["line"]
            if touches(ln, ln):
                report(rel, ln, "comments/aside", "parenthetical aside in a comment. Fix: make it a plain sentence, or delete it.")


def next_code_line(sorted_lines, after):
    for ln in sorted_lines:
        if ln > after:
            return ln
    return None


def nxt_stmt_after(sorted_lines, end, comment_line):
    """True when no code sits between the function end and the comment, so the comment trails the body."""
    return not any(end < ln < comment_line for ln in sorted_lines)


def main():
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

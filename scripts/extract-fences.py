#!/usr/bin/env python3
"""Extract the copy-verbatim fences from the scaffold markdown into a file tree.

A copy-verbatim fence is the first fence after a path heading, written **`<path>`** (kit
files), ### `<path>` (stack files), or as a prose line that ends in a colon and says
"Create `<path>`". A heading followed by "Empty file" is a 0-byte file.

A "**For TS..." / "**For FastAPI..." label before a fence marks a per-stack variant. A
shell script fence must open with a shebang; anything else after its heading is a command to
run, not a file.

A file that lives in a template tree has no fence. Its markdown entry is one line that starts
at column 0 with the backticked path and names a `<skill-dir>/shared/template...` file in
backticks on that same line. That pointer line closes the current heading, so the fences after
it are not read as that heading's file. A pointer inside a bullet, a blockquote or a table, or
one split over two lines, does not match and does not close the heading.

Stack mode (the golden tree):
  extract-fences.py --stack {nextjs,vite-react,fastapi,nestjs} --ci {github,azure} --out DIR
    Reads the files the scaffold loads for that stack, writes each fence to
    DIR/<path>, keeps only the variant that matches the stack and the CI host's
    pipeline file, and composes the FastAPI `quality` job into the shared ci.yml.

Flat mode (hook tests):
  extract-fences.py --flat [--ext sh,cjs,py] --out DIR --src FILE [FILE ...]
    Writes DIR/<stem>[.ts|.py]<ext>, one per fence, each source parsed on its own.

stdout: "<sha256>  <path>" per written file, sorted by path.
stderr: "skipped <src>:<line> <reason>" per fence that is not written.
Exit: 0 ok, 2 parse error.
"""
import argparse
import hashlib
import os
import re
import sys

SCAFFOLD = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skills", "scaffold"))
TS_STACKS = ("nextjs", "vite-react", "nestjs")
STACKS = TS_STACKS + ("fastapi",)
CI_FILE = {"github": ".github/workflows/ci.yml", "azure": "azure-pipelines/templatecentral-gates.yml"}
HEADING = re.compile(r"^(?:\*\*|#{2,4} )`([^`\s]+)`")
TAG_EXT = {"bash": {"sh"}, "sh": {"sh"}, "shell": {"sh"}, "json": {"json"}, "python": {"py"}, "py": {"py"},
           "yaml": {"yaml", "yml"}, "yml": {"yaml", "yml"}, "toml": {"toml"}}
POINTER = re.compile(r"^`[^`\s]+`.*`<skill-dir>/shared/template[^`]*`")
CREATE = re.compile(r"[Cc]reate `([^`\s]+)`")
OPENER = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
EXTENSIONLESS = {"Dockerfile", "Makefile", "CODEOWNERS", "LICENSE", "Procfile", "Jenkinsfile"}


def is_file_heading(path):
    base = os.path.basename(path)
    return ":" not in path and not path.endswith("/") and "<" not in path and ("." in base.lstrip(".") or base.startswith(".") or "/" in path or base in EXTENSIONLESS)


def sources_for(stack):
    variant = "ts" if stack in TS_STACKS else "fastapi"
    return [
        f"{stack}/source-files.md",
        "shared/harness-kit.md",
        f"shared/harness-kit-{variant}.md",
        "shared/harness-kit-enforcement.md",
        "shared/harness-kit-finalize.md",
        "shared/documentation-kit.md",
    ]


def parse(src_path, label):
    """Yield events from one markdown file:
      ("fence", path, variant, line, body)   a fence under a path heading
      ("skip", None, None, line, reason)     a fence that is not a file
      ("unfenced", path, None, line, reason) a path heading that yielded no file
    Fences follow CommonMark: a run of 3+ backticks or tildes opens, and only the
    same character in a run at least as long closes. Any opener counts, tagged or bare.
    One deliberate extension: a tagged opener of the same kind inside a fence is a nested
    snippet whose own closer does not end the outer fence, because several skill bodies
    embed a ```bash block inside a ``` block and an LLM reads them as one file."""
    with open(src_path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    path = variant = None
    path_line = 0
    seen_variant = False
    satisfied = False
    created_path = False

    def drop():
        nonlocal path
        if path and not satisfied:
            return ("unfenced", path, None, path_line, "heading has no file-yielding fence")
        return None

    i = 0
    while i < len(lines):
        line = lines[i]
        m = HEADING.match(line)
        created = False
        if not m and line.rstrip().endswith(":") and not line.startswith("#"):
            m = CREATE.search(line)
            created = m is not None
        om = OPENER.match(line)
        if m and is_file_heading(m.group(1)):
            ev = drop() if m.group(1) != path else None
            if ev:
                yield ev
            path, variant, path_line, seen_variant, satisfied = m.group(1), None, i + 1, False, False
            created_path = created
            nxt = next((l for l in lines[i + 1:i + 6] if l.strip()), "")
            if nxt.startswith("Empty file"):
                yield "fence", path, None, i + 1, []
                path, satisfied = None, True
        elif POINTER.match(line):
            ev = drop()
            if ev:
                yield ev
            path = variant = None
            seen_variant = satisfied = created_path = False
        elif line.startswith("**For TS"):
            variant = "ts"
        elif line.startswith("**For FastAPI"):
            variant = "py"
        elif om:
            fence_char, run = om.group(1)[0], len(om.group(1))
            j, depth = i + 1, 0
            while j < len(lines):
                cm = re.match(r"^ {0,3}(`+|~+)\s*$", lines[j])
                nested = OPENER.match(lines[j])
                if cm and cm.group(1)[0] == fence_char and len(cm.group(1)) >= run:
                    if depth == 0:
                        break
                    depth -= 1
                elif nested and nested.group(1)[0] == fence_char and len(nested.group(1)) >= run and nested.group(2).strip():
                    depth += 1
                j += 1
            if j >= len(lines):
                raise ValueError(f"{label}:{i + 1} unterminated fence")
            body = lines[i + 1:j]
            tag = om.group(2).strip().split(" ")[0].lower()
            ext = os.path.splitext(path)[1].lstrip(".") if path else ""
            if path and created_path and tag in TAG_EXT and ext not in TAG_EXT[tag]:
                raise ValueError(f"{label}:{i + 1} a {tag} fence follows 'Create `{path}`:'; that is a command, not the file")
            if not path:
                yield "skip", None, None, i + 1, "no path heading"
            elif seen_variant and not variant:
                yield "skip", None, None, i + 1, f"fence after the variants of {path} has no variant label"
            elif path.endswith(".sh") and not (body and body[0].startswith("#!")):
                yield "skip", None, None, i + 1, f"not a script body for {path}"
                if not variant:
                    ev = drop()
                    if ev:
                        yield ev
                    path = None
            else:
                yield "fence", path, variant, i + 1, body
                satisfied = True
                if variant:
                    seen_variant, variant = True, None
                else:
                    path = None
            i = j
        i += 1
    ev = drop()
    if ev:
        yield ev


def write(out, rel, body):
    if os.path.isabs(rel) or ".." in rel.split("/"):
        raise ValueError(f"unsafe path {rel}")
    dest = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    data = ("\n".join(body) + "\n") if body else ""
    with open(dest, "w", encoding="utf-8", newline="") as fh:
        fh.write(data)
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def compose_quality_job(base, fragment):
    lines = base.split("\n")
    start = next((n for n, l in enumerate(lines) if l == "  quality:"), None)
    if start is None:
        raise ValueError("shared ci.yml has no quality job to replace")
    end = start + 1
    while end < len(lines) and not re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[end]):
        end += 1
    return "\n".join(lines[:start] + fragment.split("\n") + lines[end:])


def run_stack(stack, ci, out):
    variant_want = "ts" if stack in TS_STACKS else "py"
    other_ci = CI_FILE["azure" if ci == "github" else "github"]
    files, fragments = {}, {}
    for rel_src in sources_for(stack):
        src = os.path.join(SCAFFOLD, rel_src)
        for kind, path, variant, line, body in parse(src, rel_src):
            where = f"{rel_src}:{line}"
            if kind == "unfenced":
                print(f"unfenced {where} {path}", file=sys.stderr)
            elif kind == "skip":
                print(f"skipped {where} {body}", file=sys.stderr)
            elif variant and variant != variant_want:
                print(f"skipped {where} variant {variant} not used by {stack}", file=sys.stderr)
            elif path == other_ci:
                print(f"skipped {where} {path} belongs to the other CI host", file=sys.stderr)
            elif path == CI_FILE["github"] and body and body[0].startswith("  quality:"):
                fragments[path] = (where, body)
            elif path in files:
                raise ValueError(f"{where} duplicates {path} from {files[path][0]}")
            else:
                files[path] = (where, body)
    for path, (where, body) in fragments.items():
        if path not in files:
            raise ValueError(f"{where} fragment has no base file {path}")
        composed = compose_quality_job("\n".join(files[path][1]), "\n".join(body))
        files[path] = (files[path][0], composed.split("\n"))
    return {p: write(out, p, b) for p, (_, b) in files.items()}


def run_flat(srcs, exts, out):
    os.makedirs(out, exist_ok=True)
    hashes = {}
    for src in srcs:
        for kind, path, variant, line, body in parse(src, src):
            if kind == "unfenced":
                print(f"unfenced {src}:{line} {path}", file=sys.stderr)
                continue
            if kind == "skip":
                print(f"skipped {src}:{line} {body}", file=sys.stderr)
                continue
            stem, ext = os.path.splitext(os.path.basename(path))
            if exts and ext.lstrip(".") not in exts:
                print(f"skipped {src}:{line} extension of {path} not requested", file=sys.stderr)
                continue
            name = stem + ("." + variant if variant else "") + ext
            hashes[name] = write(out, name, body)
    return hashes


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stack", choices=STACKS)
    ap.add_argument("--ci", choices=sorted(CI_FILE))
    ap.add_argument("--out", required=True)
    ap.add_argument("--flat", action="store_true")
    ap.add_argument("--ext", default="")
    ap.add_argument("--src", nargs="+", default=[])
    args = ap.parse_args()
    try:
        if args.flat:
            if not args.src:
                ap.error("--flat needs --src")
            hashes = run_flat(args.src, {e for e in args.ext.split(",") if e}, args.out)
        else:
            if not (args.stack and args.ci):
                ap.error("--stack and --ci are required")
            hashes = run_stack(args.stack, args.ci, args.out)
    except (OSError, ValueError) as err:
        print(f"extract-fences: {err}", file=sys.stderr)
        return 2
    for path in sorted(hashes):
        print(f"{hashes[path]}  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Extract the copy-verbatim fences from the scaffold markdown into a file tree.

A copy-verbatim fence is the first fence after a path heading, written either
**`<path>`** (kit files) or ### `<path>` (stack files). A "**For TS..." /
"**For FastAPI..." label before a fence marks a per-stack variant. A shell
script fence must open with a shebang; anything else after its heading is a
command to run, not a file.

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
HEADING = re.compile(r"^(?:\*\*|#{2,4} )`([^`\s<>*]+)`")


def sources_for(stack):
    variant = "ts" if stack in TS_STACKS else "fastapi"
    return [
        f"{stack}/config-files.md",
        f"{stack}/source-files.md",
        "shared/harness-kit.md",
        f"shared/harness-kit-{variant}.md",
        "shared/harness-kit-enforcement.md",
        "shared/harness-kit-finalize.md",
        "shared/documentation-kit.md",
    ]


def parse(src_path, label):
    """Yield (path, variant, line_no, body) for each fence under a path heading;
    yield (None, None, line_no, reason) for each fence that is skipped."""
    with open(src_path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    path = variant = None
    i = 0
    while i < len(lines):
        line = lines[i]
        m = HEADING.match(line)
        if m and ("." in os.path.basename(m.group(1)) or m.group(1) == "Dockerfile"):
            path, variant = m.group(1), None
        elif line.startswith("**For TS"):
            variant = "ts"
        elif line.startswith("**For FastAPI"):
            variant = "py"
        elif line.startswith("```") and len(line) > 3:
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            if j >= len(lines):
                raise ValueError(f"{label}:{i + 1} unterminated fence")
            body = lines[i + 1:j]
            if not path:
                yield None, None, i + 1, "no path heading"
            elif path.endswith(".sh") and not (body and body[0].startswith("#!")):
                yield None, None, i + 1, f"not a script body for {path}"
            else:
                yield path, variant, i + 1, body
                if not variant:
                    path = None
            i = j
        i += 1


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
    out, lines, i = [], base.split("\n"), 0
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
        for path, variant, line, body in parse(src, rel_src):
            where = f"{rel_src}:{line}"
            if path is None:
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
        for path, variant, line, body in parse(src, src):
            if path is None:
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

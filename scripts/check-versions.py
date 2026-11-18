#!/usr/bin/env python3
"""Fail when a file disagrees with skills/scaffold/shared/versions.txt.

Checked: template package.json and requirements files, Dockerfiles, CI templates, seeded scripts,
version tokens in template files, GitHub Action pins in skills/ and .github/, pip/npm specs in skill
code fences, and skill prose that states a version for a listed package.

Usage: check-versions.py [--root DIR]   (default: the repository root)
"""
import json
import re
import sys
from pathlib import Path

VERSIONS = "skills/scaffold/shared/versions.txt"
TEXT_SUFFIXES = {".md", ".tmpl", ".sh", ".yml", ".yaml", ".json", ".toml", ".txt", ".properties",
                 ".py", ".cjs", ".mjs", ".cfg", ".ini", ".env", ".example", ""}
errors = []


def err(path, line, msg):
    errors.append(f"{path}:{line}: {msg}")


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def load(root):
    cfg = {"npm": {}, "pip": {}, "tool": {}, "action": {}, "image": {}, "node": {}, "python": {}, "pnpm": None}
    text = read(root / VERSIONS)
    if text is None:
        sys.exit(f"check-versions: {VERSIONS} not found under {root}")
    for n, raw in enumerate(text.splitlines(), 1):
        f = raw.split("#", 1)[0].split()
        if not f:
            continue
        kind, rest = f[0], f[1:]
        if kind in ("npm", "pip", "tool", "image") and len(rest) == 2:
            cfg[kind][rest[0]] = rest[1]
        elif kind in ("node", "python") and len(rest) == 2:
            cfg[kind][rest[0]] = rest[1]
        elif kind == "pnpm" and len(rest) == 1:
            cfg["pnpm"] = rest[0]
        elif kind == "action" and len(rest) == 3:
            cfg["action"][rest[0]] = (rest[1], rest[2])
        else:
            err(VERSIONS, n, f"unreadable record: {raw.strip()}")
    for need in (("node", "major"), ("node", "min"), ("python", "minor")):
        if need[1] not in cfg[need[0]]:
            err(VERSIONS, 0, f"missing record: {need[0]} {need[1]}")
    if not cfg["pnpm"]:
        err(VERSIONS, 0, "missing record: pnpm")
    return cfg


def base(spec):
    return re.sub(r"^[\^~>=<]+", "", spec)


def resolve(cfg, value):
    if value.startswith("npm:"):
        return base(cfg["npm"].get(value[4:], "?"))
    if value.startswith("pip:"):
        return base(cfg["pip"].get(value[4:], "?"))
    return value


def files(root, *globs):
    seen = set()
    for g in globs:
        for p in sorted(root.glob(g)):
            if p.is_file() and p not in seen and "node_modules" not in p.parts:
                seen.add(p)
                yield p


def in_template(p, root):
    return any(part == "template" or part.startswith("template-") for part in p.relative_to(root).parts[:-1])


def rel(p, root):
    return str(p.relative_to(root))


def split_md(text):
    """Return (code_mask) per character: 1 inside a fenced block or an inline code span."""
    mask = [0] * len(text)
    for m in re.finditer(r"^( *)(`{3,}|~{3,}).*?^\1\2[ \t]*$", text, re.S | re.M):
        for i in range(m.start(), m.end()):
            mask[i] = 1
    for m in re.finditer(r"`[^`\n]+`", text):
        if not mask[m.start()]:
            for i in range(m.start(), m.end()):
                mask[i] = 2
    return mask


def lineno(text, pos):
    return text.count("\n", 0, pos) + 1


PIP_SPEC = r"(?:>=|~=|==|<=|!=|<|>)[0-9][0-9A-Za-z.*]*(?:,\s*(?:>=|<=|<|>)[0-9][0-9A-Za-z.*]*)?"


def pip_re(name):
    return re.compile(r"(?<![\w.\-/])" + re.escape(name) + r"(?:\[[^\]]*\])?(" + PIP_SPEC + ")")


def check_package_json(cfg, root):
    node_min, node_major = cfg["node"].get("min", "?"), cfg["node"].get("major", "?")
    for p in files(root, "skills/**/package.json"):
        if not in_template(p, root):
            continue
        r = rel(p, root)
        try:
            data = json.loads(read(p))
        except (TypeError, ValueError):
            err(r, 1, "not valid JSON")
            continue
        for section in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
            for name, spec in (data.get(section) or {}).items():
                want = cfg["npm"].get(name)
                if want is None:
                    err(r, 1, f"{name} is not listed in versions.txt")
                elif spec != want:
                    err(r, 1, f"{name} is {spec}, versions.txt says {want}")
        pm = data.get("packageManager")
        if pm is not None and pm != f"pnpm@{cfg['pnpm']}":
            err(r, 1, f"packageManager is {pm}, versions.txt says pnpm@{cfg['pnpm']}")
        eng = (data.get("engines") or {}).get("node")
        if eng is not None and eng != f">={node_min}":
            err(r, 1, f"engines.node is {eng}, versions.txt says >={node_min}")
    want = f"^{node_major}"
    if "@types/node" in cfg["npm"] and cfg["npm"]["@types/node"] != want:
        err(VERSIONS, 0, f"@types/node is {cfg['npm']['@types/node']}, the node major is {node_major} (expected {want})")


def check_requirements(cfg, root):
    for p in files(root, "skills/**/requirements*.txt"):
        if not in_template(p, root):
            continue
        r = rel(p, root)
        for n, raw in enumerate(read(p).splitlines(), 1):
            line = raw.split("#", 1)[0].strip()
            if not line or line.startswith("-"):
                continue
            m = re.match(r"^([A-Za-z0-9_.\-]+)(?:\[[^\]]*\])?(.*)$", line)
            name, spec = m.group(1), m.group(2).strip().replace(" ", "")
            want = cfg["pip"].get(name)
            if want is None:
                err(r, n, f"{name} is not listed in versions.txt")
            elif spec != want:
                err(r, n, f"{name} is '{spec or 'unpinned'}', versions.txt says {want}")


def check_images(cfg, root):
    pat = re.compile(r"(?<![\w/.\-])(node|python|nginx):([\w][\w.\-]*)")
    for p in files(root, "skills/**/Dockerfile*", "skills/**/*.yml", "skills/**/*.yaml"):
        if not in_template(p, root):
            continue
        for n, line in enumerate(read(p).splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for m in pat.finditer(line):
                got, want = m.group(0), cfg["image"].get(m.group(1))
                if want is None:
                    err(rel(p, root), n, f"{got}: no image record for {m.group(1)}")
                elif got != want:
                    err(rel(p, root), n, f"{got} but versions.txt says {want}")
    n_ref = cfg["image"].get("node", "")
    if n_ref and not n_ref.startswith(f"node:{cfg['node'].get('major', '?')}-"):
        err(VERSIONS, 0, f"image node {n_ref} does not match the node major {cfg['node'].get('major')}")
    p_ref = cfg["image"].get("python", "")
    if p_ref and not p_ref.startswith(f"python:{cfg['python'].get('minor', '?')}."):
        err(VERSIONS, 0, f"image python {p_ref} does not match the python minor {cfg['python'].get('minor')}")


def check_tools_and_ci(cfg, root):
    keys = {k.lower().replace("_", "") + "version": (k, v) for k, v in cfg["tool"].items()}
    var = re.compile(r"\b([A-Za-z][A-Za-z_]*)\b\s*[:=]\s*[\"']?v?(\d+(?:\.\d+)+)[\"']?(?=\s|$|[\"'#;)])")
    node_major, py_minor = cfg["node"].get("major", "?"), cfg["python"].get("minor", "?")
    node_pats = [re.compile(r"node-version:\s*[\"']?(\d+)"), re.compile(r"versionSpec:\s*[\"'](\d+)\.x[\"']"),
                 re.compile(r"displayName:\s*Node (\d+)\b")]
    py_pats = [re.compile(r"python-version:\s*[\"']?(3\.\d+)"), re.compile(r"versionSpec:\s*[\"'](3\.\d+)[\"']"),
               re.compile(r"displayName:\s*Python (3\.\d+)\b"), re.compile(r"sonar\.python\.version=(3\.\d+)"),
               re.compile(r"\"pythonVersion\":\s*\"(3\.\d+)\""), re.compile(r"python(3\.\d+) -m venv")]
    scan = list(files(root, "skills/**/*.sh", "skills/**/*.yml", "skills/**/*.yaml", "skills/**/*.properties",
                      "skills/**/*.json", "skills/**/*.md", "skills/**/*.toml", ".github/**/*.yml", "scripts/deploy-smoke.sh"))
    for p in scan:
        if p == root / VERSIONS:
            continue
        text = read(p)
        if text is None:
            continue
        r = rel(p, root)
        is_md = p.suffix == ".md"
        mask = split_md(text) if is_md else None
        offsets, pos = [], 0
        for line in text.splitlines(True):
            offsets.append(pos)
            pos += len(line)
        for n, line in enumerate(text.splitlines(), 1):
            def fenced(m):
                return not is_md or mask[offsets[n - 1] + m.start()] == 1

            for m in var.finditer(line):
                if not fenced(m):
                    continue
                hit = keys.get(m.group(1).lower().replace("_", ""))
                if hit is None and m.group(1).lower().replace("_", "") + "version" in keys:
                    hit = keys[m.group(1).lower().replace("_", "") + "version"]
                if hit is None:
                    continue
                want = resolve(cfg, hit[1])
                if m.group(2) != want:
                    err(r, n, f"{m.group(1)} is {m.group(2)}, versions.txt says {want}")
            for pat in node_pats:
                for m in pat.finditer(line):
                    if fenced(m) and m.group(1) != node_major:
                        err(r, n, f"Node {m.group(1)} but versions.txt says {node_major}")
            for pat in py_pats:
                for m in pat.finditer(line):
                    if not fenced(m):
                        continue
                    got = m.group(1) if "." in m.group(1) else "3." + m.group(1)
                    if got != py_minor:
                        err(r, n, f"Python {got} but versions.txt says {py_minor}")
    for p in files(root, "skills/**/pyproject.toml"):
        if not in_template(p, root):
            continue
        for n, line in enumerate(read(p).splitlines(), 1):
            m = re.match(r"\s*target-version\s*=\s*\"py(3)(\d+)\"", line)
            if m and f"3.{m.group(2)}" != py_minor:
                err(rel(p, root), n, f"ruff target py3{m.group(2)} but versions.txt says python {py_minor}")


def check_template_tokens(cfg, root):
    node_min, py_minor = cfg["node"].get("min", "?"), cfg["python"].get("minor", "?")
    pnpm_major = (cfg["pnpm"] or "?").split(".")[0]
    for p in files(root, "skills/**/*"):
        if not in_template(p, root) or p.suffix in (".json", ".lock") or p.name == "pnpm-workspace.yaml":
            continue
        text = read(p)
        if text is None:
            continue
        r = rel(p, root)
        for n, line in enumerate(text.splitlines(), 1):
            for m in re.finditer(r"\bNode(?:\.js)? ≥\s?(\d+(?:\.\d+)*)", line):
                if m.group(1) != node_min:
                    err(r, n, f"Node ≥{m.group(1)} but versions.txt says {node_min}")
            for m in re.finditer(r"\bPython (3\.\d+)\b", line):
                if m.group(1) != py_minor:
                    err(r, n, f"Python {m.group(1)} but versions.txt says {py_minor}")
            for m in re.finditer(r"\bpnpm (\d+)\b", line):
                if m.group(1) != pnpm_major:
                    err(r, n, f"pnpm {m.group(1)} but versions.txt says pnpm {cfg['pnpm']}")


def check_actions(cfg, root):
    pat = re.compile(r"\buses:\s*([\w.\-]+/[\w.\-]+)(?:/[\w./\-]+)?@(\S+?)(?:[ \t]+#[ \t]*(\S+))?[ \t]*$")
    for p in files(root, "skills/**/*", ".github/**/*.yml"):
        if p == root / VERSIONS or p.suffix in (".json", ".lock"):
            continue
        text = read(p)
        if text is None or "uses:" not in text:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            m = pat.search(line)
            if not m or line.lstrip().startswith("#"):
                continue
            repo, ref, tag = m.group(1), m.group(2), m.group(3)
            want = cfg["action"].get(repo)
            if want is None:
                err(rel(p, root), n, f"action {repo} is not listed in versions.txt")
            elif ref != want[0] or tag != want[1]:
                err(rel(p, root), n, f"{repo}@{ref[:12]} # {tag} but versions.txt says {want[0][:12]} # {want[1]}")


def check_pip_and_npm_in_text(cfg, root):
    pips = {name: pip_re(name) for name in cfg["pip"]}
    install = re.compile(r"\b(?:pnpm (?:add|install|i)|npm (?:i|install)|pip install|pip3 install)\b")
    npm_at = re.compile(r"(?<![\w@/.\-])(@?[a-z][\w.\-]*(?:/[\w.\-]+)?)@(\^|~)?(\d[\w.\-]*)")
    prose_forms = {}
    for name in list(cfg["npm"]) + list(cfg["pip"]):
        n = re.escape(name)
        prose_forms[name] = re.compile(
            r"(?<![\w@/.\-])" + n + r"(?![\w\-/])(?:\s*(?:@|≥|>=|\^|~|==)\s*v?\d|\s+v?\d+\.\d)")
    for p in files(root, "skills/**/*", "scripts/deploy-smoke.sh"):
        if p == root / VERSIONS or p.suffix in (".json", ".lock") or in_template(p, root) and p.suffix != ".md":
            continue
        text = read(p)
        if text is None:
            continue
        r = rel(p, root)
        is_md = p.suffix == ".md" and not in_template(p, root)
        mask = split_md(text) if is_md else [1] * len(text)
        for name, rx in pips.items():
            for m in rx.finditer(text):
                spec = m.group(1).replace(" ", "")
                n = lineno(text, m.start())
                if mask[m.start()] == 0:
                    err(r, n, f"prose states a version for {name}")
                elif spec != cfg["pip"][name]:
                    err(r, n, f"{name}{spec} but versions.txt says {cfg['pip'][name]}")
        if not is_md:
            continue
        for m in npm_at.finditer(text):
            name, spec = m.group(1), (m.group(2) or "") + m.group(3)
            if name not in cfg["npm"] or mask[m.start()] == 0:
                continue
            if spec != cfg["npm"][name]:
                err(r, lineno(text, m.start()), f"{name}@{spec} but versions.txt says {cfg['npm'][name]}")
        for name, rx in prose_forms.items():
            for m in rx.finditer(text):
                k = mask[m.start()]
                if k == 1:
                    continue
                if k == 2:
                    span = text.rfind("`", 0, m.start())
                    if install.search(text[span:m.start()]):
                        continue
                if name in cfg["pip"] and pip_re(name).match(text, m.start()):
                    continue
                err(r, lineno(text, m.start()), f"prose states a version for {name}")


def main(argv):
    root = Path(__file__).resolve().parent.parent
    if "--root" in argv:
        root = Path(argv[argv.index("--root") + 1]).resolve()
    cfg = load(root)
    check_package_json(cfg, root)
    check_requirements(cfg, root)
    check_images(cfg, root)
    check_tools_and_ci(cfg, root)
    check_template_tokens(cfg, root)
    check_actions(cfg, root)
    check_pip_and_npm_in_text(cfg, root)
    if errors:
        for e in sorted(set(errors)):
            print(e)
        print(f"check-versions: {len(set(errors))} disagreement(s) with {VERSIONS}")
        return 1
    print(f"check-versions: ok ({sum(len(cfg[k]) for k in ('npm', 'pip', 'tool', 'action', 'image'))} records)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

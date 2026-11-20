# Lists the project Python environment for check-licences.sh and generate-sbom.sh; limit: a marker line that applies here but is not installed passes, and the SBOM omits it.
import datetime
import importlib.metadata as md
import json
import os
import re
import sys
import uuid


def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def stop(message):
    """Prints the message and exits 3, which means a wrong project or document."""
    sys.stderr.write(message + "\n")
    sys.exit(3)


def licence(meta):
    """Returns the licence text and whether it is an SPDX expression, from License-Expression, License, then classifiers joined with AND."""
    expr = " ".join((meta.get("License-Expression") or "").split())
    if expr:
        return expr, True
    text = " ".join((meta.get("License") or "").split())
    if text and "\n" not in text and len(text) <= 100 and text.upper() != "UNKNOWN":
        return text, False
    labels = [" ".join(c.split("::")[-1].split()) for c in meta.get_all("Classifier") or [] if c.startswith("License ::")]
    labels = sorted({x for x in labels if x != "OSI Approved"})
    return (" AND ".join(labels), False) if labels else ("Unknown", False)


def installed():
    """Returns a map of named distributions and a list of dist-info folders that have no Name."""
    named, nameless = {}, []
    for d in md.distributions():
        name = d.metadata.get("Name")
        if name:
            named.setdefault((norm(name), d.version), (name, d))
        else:
            path = getattr(d, "_path", None)
            nameless.append(os.path.basename(str(path)) if path else "an unnamed distribution")
    return named, sorted(set(nameless))


ALLOWED_OPTIONS = {"--hash", "-e", "--editable", "-i", "--index-url", "--extra-index-url", "-f", "--find-links", "--no-binary", "--only-binary", "--trusted-host", "--prefer-binary", "--require-hashes"}


def wanted(path, strict):
    """Returns the normalised names in requirements.txt: those that must be installed, and those behind an environment marker."""
    required, optional = [], []
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    continued = False
    for raw in lines:
        skip = continued
        continued = raw.rstrip().endswith("\\")
        line = re.sub(r"\s#.*$", "", raw.strip())
        if skip or not line or line.startswith("#"):
            continue
        if line.startswith("-"):
            if strict and re.split(r"[=\s]", line, 1)[0] not in ALLOWED_OPTIONS:
                stop("%s has the line '%s', which is not a plain requirement or a known pip option (an include such as -r or -c escapes the prod check). The hashed lock must be self-contained, so compile it into one requirements.txt." % (path, line))
            continue
        m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", line)
        if not m:
            continue
        marked = ";" in line and line.split(";", 1)[1].strip().rstrip("\\").strip() != ""
        (optional if marked else required).append(norm(m.group(0)))
    return required, optional


def require_installed(req, named, strict):
    """Stops when a package named in requirements.txt without a marker is not installed; returns every locked name."""
    if not req:
        return set()
    required, optional = wanted(req, strict)
    have = {k for (k, _v) in named}
    missing = sorted({n for n in required if n not in have})
    if missing:
        stop("%s lists %s, which %s not installed. Install first: uv pip install --require-hashes -r requirements.txt" % (req, ", ".join(missing[:5]), "is" if len(missing) == 1 else "are"))
    return set(required) | set(optional)


def cmd_licences(req, scope):
    named, nameless = installed()
    names = require_installed(req, named, scope != "all")
    locked = names if req and scope != "all" else None
    for key, version in sorted(named):
        if locked is not None and key not in locked:
            continue
        name, d = named[(key, version)]
        print("%s@%s\t%s" % (name, version, licence(d.metadata)[0]))
    for folder in nameless:
        print("%s@?\tUnknown" % folder)


def cmd_sbom(req, out):
    named, nameless = installed()
    if nameless:
        stop("the environment has a package with no Name in its metadata (%s), so it cannot be listed." % ", ".join(nameless[:3]))
    require_installed(req, named, True)
    latest = {}
    for (key, _version), (_name, d) in sorted(named.items()):
        latest.setdefault(key, d)
    components, dependencies = [], []
    for key in sorted(latest):
        d = latest[key]
        ref = "pkg:pypi/%s@%s" % (key, d.version)
        component = {"type": "library", "bom-ref": ref, "name": d.metadata["Name"], "version": d.version, "purl": ref}
        text, is_expr = licence(d.metadata)
        if text != "Unknown":
            component["licenses"] = [{"expression": text}] if is_expr else [{"license": {"name": text}}]
        components.append(component)
        depends = set()
        for r in d.requires or []:
            if ";" in r and "extra" in r.split(";", 1)[1]:
                continue
            m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", r.strip())
            if m and norm(m.group(0)) in latest:
                depends.add("pkg:pypi/%s@%s" % (norm(m.group(0)), latest[norm(m.group(0))].version))
        dependencies.append({"ref": ref, "dependsOn": sorted(depends)})
    if not components:
        stop("the project environment has no packages installed.")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    doc = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": "urn:uuid:" + str(uuid.uuid4()),
        "version": 1,
        "metadata": {"timestamp": stamp, "tools": {"components": [{"type": "application", "name": "generate-sbom.sh"}]}},
        "components": components,
        "dependencies": dependencies,
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")


def cmd_check(path):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except ValueError:
        stop("the Python SBOM is not valid JSON.")
    if not isinstance(doc, dict) or doc.get("bomFormat") != "CycloneDX" or not isinstance(doc.get("components"), list):
        stop("the Python SBOM is not a CycloneDX document with a components array.")
    if not doc["components"]:
        stop("the Python SBOM has no components.")


def main(argv):
    if len(argv) == 4 and argv[1] == "licences":
        cmd_licences(argv[2], argv[3])
    elif len(argv) == 4 and argv[1] == "sbom":
        cmd_sbom(argv[2], argv[3])
    elif len(argv) == 3 and argv[1] == "check":
        cmd_check(argv[2])
    else:
        sys.exit("usage: py-env.py licences <requirements.txt or ''> <prod|all> | sbom <requirements.txt or ''> <out> | check <file>")


main(sys.argv)

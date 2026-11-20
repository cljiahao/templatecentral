# Lists the packages in the project Python environment for check-licences.sh and generate-sbom.sh; exit 3 means a wrong project or document.
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


def wanted(path):
    """Returns the normalised names in requirements.txt and the count of marker lines that could not be evaluated."""
    try:
        from packaging.markers import Marker
    except ImportError:
        Marker = None
    names, unchecked = [], 0
    for raw in open(path, encoding="utf-8"):
        if not raw.strip() or raw[0] in " \t#-":
            continue
        m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", raw)
        if not m:
            continue
        marker = raw.split(";", 1)[1].strip().rstrip("\\").strip() if ";" in raw else ""
        if marker:
            if Marker is None:
                unchecked += 1
                continue
            if not Marker(marker).evaluate():
                continue
        names.append(norm(m.group(0)))
    return names, unchecked


def require_installed(req, named):
    """Stops when a package named in requirements.txt is not installed; returns the unchecked-marker count."""
    if not req:
        return 0
    names, unchecked = wanted(req)
    have = {k for (k, _v) in named}
    missing = sorted({n for n in names if n not in have})
    if missing:
        stop("%s lists %s, which %s not installed. Install first: uv pip install --require-hashes -r requirements.txt" % (req, ", ".join(missing[:5]), "is" if len(missing) == 1 else "are"))
    return unchecked


def cmd_licences(req, scope):
    named, nameless = installed()
    require_installed(req, named)
    locked = None
    if req and scope != "all":
        locked = set(wanted(req)[0])
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
    require_installed(req, named)
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

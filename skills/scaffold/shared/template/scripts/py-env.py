# Environment lister for check-licences.sh and generate-sbom.sh; an applicable but uninstalled marker line passes.
import datetime
import importlib.metadata as md
import json
import os
import re
import shlex
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


NAME = r"[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?"
REQUIREMENT = re.compile(r"^(" + NAME + r")(?:\[[A-Za-z0-9._,\s-]*\])?==([A-Za-z0-9._+!-]+)\s*(?:;\s*(\S.*?))?\s*$")
HASH = re.compile(r"^--hash=[A-Za-z0-9_]+:[0-9a-fA-F]+$")
OPTION_ARGS = {"--index-url": 1, "-i": 1, "--extra-index-url": 1, "--find-links": 1, "-f": 1, "--trusted-host": 1, "--no-binary": 1, "--only-binary": 1, "--prefer-binary": 0, "--require-hashes": 0}


def why(line):
    """Returns a short reason a line is not part of a hashed lock."""
    if re.match(r"-(e|r|c)|--(editable|requirement|constraint)", line):
        return "an editable or an include adds packages outside the lock"
    if "@" in line or "://" in line or line[0] in "./~" or re.match(r"(git|hg|svn|bzr)\+", line):
        return "a direct reference, URL, path or VCS requirement is not pinned by hash"
    if re.search(r"[<>~!]=|[<>]|===", line):
        return "only name==version is allowed"
    return "it is not name==version, a --hash line or a known global option"


def refuse(path, number, text, reason):
    """Stops with exit 3 and names the line of the hashed lock that is refused."""
    stop("%s line %d '%s': %s. The hashed lock must list every package as name==version with hashes (uv pip compile --generate-hashes), so recompile it." % (path, number, text.strip(), reason))


def read_lock(path):
    """Returns the bytes of the requirements file without a leading byte order mark."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        stop("cannot read %s: %s. The hashed lock must be a readable requirements.txt." % (path, e.strerror or e))
    return data[3:] if data.startswith(b"\xef\xbb\xbf") else data


def check_bytes(path, data):
    """Stops on a byte other than tab, LF, CRLF or printable ASCII."""
    for i, b in enumerate(data):
        if b in (9, 10) or 32 <= b <= 126:
            continue
        if b == 13 and data[i + 1 : i + 2] == b"\n":
            continue
        stop("%s line %d: byte 0x%02x is not allowed (only tab, LF, CRLF and printable ASCII), because pip may read it as a line break or another encoding. The hashed lock must be plain ASCII as uv pip compile --generate-hashes writes it, so recompile it." % (path, data.count(b"\n", 0, i) + 1, b))


def lock_lines(path):
    """Returns the lines of the requirements file after the byte and coding checks."""
    data = read_lock(path)
    check_bytes(path, data)
    lines = data.decode("ascii").replace("\r\n", "\n").split("\n")
    for number, text in enumerate(lines[:2], 1):
        if re.match(r"[ \t]*#.*?coding[:=][ \t]*[-\w.]+", text):
            stop("%s line %d '%s': a coding comment makes pip decode the file in another encoding. Remove it: the hashed lock must be plain ASCII as uv pip compile --generate-hashes writes it." % (path, number, text.strip()))
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def check_layout(path, number, raw, ends):
    """Refuses a backslash that is not last, and a # $ or tab that pip reads differently, on a line that is not a comment."""
    if raw.rstrip().endswith("\\") and not ends:
        refuse(path, number, raw, "a backslash must be the last character of the line")
    if raw.lstrip().startswith("#"):
        return
    if "#" in raw:
        refuse(path, number, raw, "a # is only allowed at the start of a line, because pip joins a continuation first and then drops everything after #, which can drop a hash")
    if "$" in raw:
        refuse(path, number, raw, "a $ is only allowed in a full-line comment, because pip expands ${VAR} before it reads the line")
    if "\t" in raw:
        refuse(path, number, raw, "a tab is only allowed in a full-line comment, because pip splits a joined line on a space only")
    if ends and not raw[:-1].endswith(" "):
        refuse(path, number, raw, "a line that continues must end with a space and then the backslash, because pip joins the lines without adding a space")


def check_hash_line(path, number, raw, body):
    """Refuses a continuation line that is not one --hash option starting with a space."""
    if not HASH.match(body.lstrip()):
        refuse(path, number, raw, "a continuation line must be --hash=<alg>:<hex> only" if body.strip() else "a continuation line is empty")
    if not raw.startswith(" "):
        refuse(path, number, raw, "a hash continuation line must start with a space, because pip joins the lines without adding one")


def check_option(path, number, raw, stripped, ends):
    """Refuses an option line that is not a known global option with its arguments."""
    if ends:
        refuse(path, number, raw, "an option line must not end with a backslash")
    try:
        tokens = shlex.split(stripped)
    except ValueError:
        refuse(path, number, raw, "the line cannot be tokenised")
    head, eq, rest = tokens[0].partition("=")
    args = ([rest] if eq else []) + tokens[1:]
    if head not in OPTION_ARGS or len(args) != OPTION_ARGS[head] or any(a.startswith("-") for a in args):
        refuse(path, number, raw, why(stripped))


def read_entry(path, number, raw, stripped, ends, found):
    """Reads one line outside a continuation and returns True when hash lines follow it."""
    if not stripped.strip() and not ends:
        return False
    if stripped.lstrip().startswith("#"):
        if ends:
            refuse(path, number, raw, "a comment line must not end with a backslash")
        return False
    if ends and not stripped.strip():
        refuse(path, number, raw, "a lone backslash line")
    if stripped.startswith("-"):
        check_option(path, number, raw, stripped, ends)
        return False
    m = REQUIREMENT.match(stripped)
    if not m:
        refuse(path, number, raw, why(stripped.strip() or raw))
    if not ends:
        refuse(path, number, raw, "a requirement needs at least one --hash continuation")
    found[1 if m.group(3) else 0].append(norm(m.group(1)))
    return True


def wanted(path):
    """Returns the normalised names in requirements.txt: those that must be installed, and those behind an environment marker."""
    lines = lock_lines(path)
    found = ([], [])
    continued = False
    for number, raw in enumerate(lines, 1):
        ends = raw.endswith("\\")
        check_layout(path, number, raw, ends)
        body = (raw[:-1] if ends else raw).rstrip()
        if continued:
            check_hash_line(path, number, raw, body)
            continued = ends
        else:
            continued = read_entry(path, number, raw, body, ends, found)
    if continued:
        refuse(path, len(lines), lines[-1], "the last line must not end with a backslash")
    return found


def require_installed(req, named):
    """Stops when a package named in requirements.txt without a marker is not installed; returns every locked name."""
    if not req:
        return set()
    required, optional = wanted(req)
    have = {k for (k, _v) in named}
    missing = sorted({n for n in required if n not in have})
    if missing:
        stop("%s lists %s, which %s not installed. Install first: uv pip install --require-hashes -r requirements.txt" % (req, ", ".join(missing[:5]), "is" if len(missing) == 1 else "are"))
    return set(required) | set(optional)


def cmd_licences(req, scope):
    named, nameless = installed()
    names = require_installed(req, named)
    locked = names if req and scope != "all" else None
    for key, version in sorted(named):
        if locked is not None and key not in locked:
            continue
        name, d = named[(key, version)]
        print("%s@%s\t%s" % (name, version, licence(d.metadata)[0]))
    for folder in nameless:
        print("%s@?\tUnknown" % folder)


def sbom_component(d, ref):
    """Returns the CycloneDX component of one distribution."""
    component = {"type": "library", "bom-ref": ref, "name": d.metadata["Name"], "version": d.version, "purl": ref}
    text, is_expr = licence(d.metadata)
    if text != "Unknown":
        component["licenses"] = [{"expression": text}] if is_expr else [{"license": {"name": text}}]
    return component


def sbom_depends(d, latest):
    """Returns the sorted refs of the installed packages a distribution requires, extras left out."""
    depends = set()
    for r in d.requires or []:
        if ";" in r and "extra" in r.split(";", 1)[1]:
            continue
        m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", r.strip())
        if m and norm(m.group(0)) in latest:
            depends.add("pkg:pypi/%s@%s" % (norm(m.group(0)), latest[norm(m.group(0))].version))
    return sorted(depends)


def write_sbom(out, components, dependencies):
    """Writes the CycloneDX document to the output file."""
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
        components.append(sbom_component(d, ref))
        dependencies.append({"ref": ref, "dependsOn": sbom_depends(d, latest)})
    if not components:
        stop("the project environment has no packages installed.")
    write_sbom(out, components, dependencies)


def cmd_check(path):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError):
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

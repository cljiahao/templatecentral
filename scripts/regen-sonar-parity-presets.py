"""Regenerate scripts/sonar-parity-presets/*.tsv from installed packages. Dev-time only; check-sonar-parity.sh never runs this.

Each snapshot records `# pin:` (the spec in skills/scaffold/shared/versions.txt) and `# version:` (the installed version it
was read from). check-sonar-parity.sh compares the pin with versions.txt and fails when they differ. After a pin bump:

  1. install the pinned packages somewhere (for example `npm pack <name>@<spec>` and extract, or any node_modules tree)
  2. python3 -I scripts/regen-sonar-parity-presets.py --sonarjs DIR --typescript-eslint DIR --eslint-js DIR \\
         --next DIR --prettier DIR --jsx-a11y DIR --ruff BIN [--sonar-meta]
     where each DIR is the package directory itself (the one holding package.json) and BIN is the ruff executable.
     Pass only the flags whose snapshots need regenerating.
  3. --sonar-meta also fetches public rule metadata (SonarJS and sonar-python repositories on raw.githubusercontent.com,
     no login, no project data) for every Sonar key in scripts/sonar-parity.tsv and writes sonar-rules.tsv.

The installed version must satisfy the pin, otherwise the script stops. Python standard library only.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LEVEL = r"(error|warn|off)"
NEXT_PREFIXES = ("react/", "react-hooks/", "@next/next/", "import/", "jsx-a11y/")


def die(msg):
    sys.exit("regen-sonar-parity-presets: " + msg)


def version_tuple(text):
    m = re.match(r"(\d+)\.(\d+)\.(\d+)", text)
    return tuple(int(x) for x in m.groups()) if m else None


def satisfies(version, spec):
    have = version_tuple(version)
    if spec.startswith(">="):
        return have >= version_tuple(spec[2:])
    if spec.startswith("^"):
        want = version_tuple(spec[1:])
        return have[0] == want[0] and have >= want
    return have == version_tuple(spec)


def pin_spec(versions, kind, name):
    with open(versions, encoding="utf-8") as fh:
        for line in fh:
            f = line.split()
            if len(f) >= 3 and f[0] == kind and f[1] == name:
                return f[2]
    die("no '%s %s' line in %s" % (kind, name, versions))


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


class Writer:
    def __init__(self, out, versions):
        self.out = out
        self.versions = versions

    def write(self, name, pins, source, columns, rows, extra=()):
        lines = []
        for kind, pkg, version in pins:
            spec = pin_spec(self.versions, kind, pkg)
            if not satisfies(version, spec):
                die("%s %s is installed at %s, which does not satisfy the pin %s" % (kind, pkg, version, spec))
            lines.append("# pin: %s %s %s" % (kind, pkg, spec))
            lines.append("# version: %s %s" % (pkg, version))
        lines.append("# source: " + source)
        lines.extend(extra)
        lines.append("# columns: " + columns)
        lines.extend("\t".join(str(c) for c in r) for r in rows)
        path = os.path.join(self.out, name + ".tsv")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        print("wrote %s (%d rows)" % (path, len(rows)))


def pkg_version(pkg_dir):
    return json.loads(read(os.path.join(pkg_dir, "package.json")))["version"]


def rule_pairs(path):
    """Every 'rule': 'level' pair in a generated config file, in order. Any other value form stops the script."""
    pairs = []
    for line in read(path).splitlines():
        m = re.match(r"\s*'([^']+)':\s*'%s'" % LEVEL, line)
        if m:
            pairs.append((m.group(1), m.group(2)))
        elif re.match(r"\s*'[^']+':\s*[\[{\d]", line) and "rules" not in line:
            die("%s: rule value form not read: %s" % (path, line.strip()))
    return pairs


def regen_sonarjs(w, pkg):
    cjs = os.path.join(pkg, "cjs")
    text = read(os.path.join(cjs, "plugin-rules.js"))
    idx = dict(re.findall(r'const (index_js_\d+) = require\("\./(S\d+)/index\.js"\)', text))
    rows = []
    for m in re.finditer(r"^\s+['\"]?([a-z0-9-]+)['\"]?: (index_js_\d+)\.rule,", text, re.M):
        meta = read(os.path.join(cjs, idx[m.group(2)], "generated-meta.js"))
        key = re.search(r"exports\.sonarKey = '([^']+)'", meta).group(1)
        desc = re.search(r"description:\s*(?:'((?:\\.|[^'\\])*)'|\"((?:\\.|[^\"\\])*)\")", meta)
        title = (desc.group(1) or desc.group(2)).replace("\\'", "'")
        rec = "error" if re.search(r"recommended: true", meta) else "off"
        rtc = 1 if re.search(r"requiresTypeChecking: true", meta) else 0
        rows.append(("sonarjs/" + m.group(1), rec, key, rtc, title))
    w.write("sonarjs-recommended", [("npm", "eslint-plugin-sonarjs", pkg_version(pkg))],
            "eslint-plugin-sonarjs configs.recommended (meta.docs.recommended true -> error, else off); name, key and "
            "requiresTypeChecking from each rule's generated-meta.js",
            "rule<TAB>level<TAB>sonar key<TAB>requires type information 0|1<TAB>name", rows)


def regen_tseslint(w, pkg):
    flat = os.path.join(pkg, "dist", "configs", "flat")
    base = rule_pairs(os.path.join(pkg, "dist", "configs", "eslint-recommended-raw.js"))
    pins = [("npm", "typescript-eslint", pkg_version(pkg))]
    for name, src in (("typescript-eslint-recommended", "recommended.js"),
                      ("typescript-eslint-recommended-type-checked", "recommended-type-checked.js")):
        rows = base + rule_pairs(os.path.join(flat, src))
        w.write(name, pins, "@typescript-eslint/eslint-plugin dist/configs/flat/%s after eslint-recommended-raw.js, "
                "later lines override earlier ones; base rules the preset turns off are kept as off" % src,
                "rule<TAB>level", rows)
    rules_dir = os.path.join(pkg, "dist", "rules")
    rows = []
    for fn in sorted(os.listdir(rules_dir)):
        if fn.endswith(".js") and fn != "index.js":
            rtc = 1 if re.search(r"requiresTypeChecking: true", read(os.path.join(rules_dir, fn))) else 0
            rows.append(("@typescript-eslint/" + fn[:-3], rtc))
    w.write("typescript-eslint-rules", pins, "@typescript-eslint/eslint-plugin dist/rules/*.js docs.requiresTypeChecking",
            "rule<TAB>requires type information 0|1", rows)


def regen_eslint_js(w, pkg):
    text = read(os.path.join(pkg, "src", "configs", "eslint-recommended.js"))
    rows = []
    for m in re.finditer(r"^\s+\"?([a-z0-9-]+)\"?:\s*\"?(error|warn|off|2|1|0)\"?", text, re.M):
        rows.append((m.group(1), {"2": "error", "1": "warn", "0": "off"}.get(m.group(2), m.group(2))))
    if not rows:
        die("no rules read from @eslint/js")
    w.write("eslint-recommended", [("npm", "@eslint/js", pkg_version(pkg))],
            "@eslint/js src/configs/eslint-recommended.js", "rule<TAB>level", rows)


def regen_next(w, pkg):
    pins = [("npm", "eslint-config-next", pkg_version(pkg))]
    ts = read(os.path.join(pkg, "dist", "typescript.js"))
    m = re.search(r"concat\(\[\s*\{\s*rules:\s*\{(.*?)\}", ts, re.S)
    if not m or "configs.recommended" not in ts:
        die("eslint-config-next/typescript no longer has the expected shape")
    rows = re.findall(r"'([^']+)':\s*'%s'" % LEVEL, m.group(1))
    w.write("next-typescript", pins, "eslint-config-next dist/typescript.js: typescript-eslint recommended, then these overrides",
            "rule<TAB>level", rows, extra=("# extends: typescript-eslint-recommended",))
    idx = read(os.path.join(pkg, "dist", "index.js"))
    keys = re.findall(r"'([^']+/[^']+)':\s*'%s'" % LEVEL, idx[idx.index("rules:"):])
    for rule, _ in keys:
        if not rule.startswith(NEXT_PREFIXES):
            die("eslint-config-next sets %s, which is outside %s" % (rule, ", ".join(NEXT_PREFIXES)))
    w.write("next-core-web-vitals", pins, "eslint-config-next dist/index.js explicit rule entries; the spread react, "
            "react-hooks and @next/next recommended sets are covered by the touches line",
            "rule<TAB>level", keys, extra=("# touches: " + " ".join(NEXT_PREFIXES),))


def regen_jsx_a11y(w, pkg):
    code = "const r = require(process.argv[1]).flatConfigs.recommended.rules; for (const k of Object.keys(r)) console.log(k + '\\t' + (Array.isArray(r[k]) ? r[k][0] : r[k]))"
    out = subprocess.run(["node", "-e", code, os.path.abspath(pkg)], check=True, capture_output=True, text=True).stdout
    rows = [tuple(line.split("\t")) for line in out.splitlines() if line]
    if not rows or any(lvl not in ("error", "warn", "off") for _, lvl in rows):
        die("eslint-plugin-jsx-a11y flatConfigs.recommended.rules no longer has the expected shape")
    w.write("jsx-a11y-recommended", [("npm", "eslint-plugin-jsx-a11y", pkg_version(pkg))],
            "eslint-plugin-jsx-a11y flatConfigs.recommended.rules, the first element of an array value is the level", "rule<TAB>level", rows)


def regen_prettier(w, pkg):
    text = read(os.path.join(pkg, "index.js"))
    body = text[text.index("exports.rules"):]
    rows = [(r, "off") for r in re.findall(r'^\s+"([^"]+)":\s*(?:"off"|0)', body, re.M)]
    if not rows:
        die("no rules read from eslint-config-prettier")
    w.write("eslint-config-prettier", [("npm", "eslint-config-prettier", pkg_version(pkg))],
            "eslint-config-prettier index.js rules, every one switched off (0 and \"off\")", "rule<TAB>level", rows,
            extra=("# touches: prettier/",))


def regen_ruff(w, binary):
    out = subprocess.run([binary, "rule", "--all", "--output-format", "json"], check=True, capture_output=True, text=True).stdout
    version = subprocess.run([binary, "--version"], check=True, capture_output=True, text=True).stdout.split()[-1]
    rows = [(r["code"], r["name"], 1 if r.get("preview") else 0) for r in json.loads(out) if r.get("code")]
    rows.sort()
    w.write("ruff-rules", [("pip", "ruff", version)], "ruff rule --all --output-format json",
            "code<TAB>name<TAB>preview-only 0|1", rows)


SONAR_JS = ("https://raw.githubusercontent.com/SonarSource/SonarJS/master/sonar-plugin/javascript-checks/src/main/resources/"
            "org/sonar/l10n/javascript/rules/javascript/%s.json")
SONAR_PY = ("https://raw.githubusercontent.com/SonarSource/sonar-python/master/python-checks/src/main/resources/"
            "org/sonar/l10n/py/rules/python/%s.json")
TYPES = {"CODE_SMELL": "code smell", "BUG": "bug", "VULNERABILITY": "vulnerability", "SECURITY_HOTSPOT": "security hotspot"}


def fetch(url):
    try:
        return json.loads(urllib.request.urlopen(url, timeout=30).read())
    except Exception:
        return None


def regen_sonar(w, table):
    keys = {"ts": set(), "py": set()}
    for line in read(table).splitlines():
        f = line.split("\t")
        if len(f) == 7 and f[1].split(":")[0] in ("typescript", "python"):
            keys[f[0]].add(f[1].split(":")[1])
    profile = fetch("https://raw.githubusercontent.com/SonarSource/sonar-python/master/python-checks/src/main/resources/"
                    "org/sonar/l10n/py/rules/python/Sonar_way_profile.json")
    if not profile:
        die("could not fetch the sonar-python Sonar way profile")
    way = set(profile["ruleKeys"])
    rows, missing = [], []
    for lang, base in (("ts", SONAR_JS), ("py", SONAR_PY)):
        for key in sorted(keys[lang]):
            meta = fetch(base % key)
            if not meta or "type" not in meta:
                missing.append("%s %s" % (lang, key))
                continue
            member = "Sonar way" in (meta.get("defaultQualityProfiles") or []) if lang == "ts" else key in way
            rows.append((lang, key, TYPES[meta["type"]], 1 if member else 0, meta["title"]))
    w.write("sonar-rules", [], "public rule metadata, SonarJS and sonar-python repositories (master); not tied to a version pin",
            "lang<TAB>key<TAB>type<TAB>in Sonar way 0|1<TAB>title", rows)
    for m in missing:
        print("not found in the public repositories (the row must say unverified): " + m)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for flag in ("sonarjs", "typescript-eslint", "eslint-js", "next", "prettier", "ruff", "jsx-a11y"):
        ap.add_argument("--" + flag)
    ap.add_argument("--sonar-meta", action="store_true")
    ap.add_argument("--out", default=os.path.join(HERE, "sonar-parity-presets"))
    ap.add_argument("--versions", default=os.path.join(ROOT, "skills", "scaffold", "shared", "versions.txt"))
    ap.add_argument("--table", default=os.path.join(HERE, "sonar-parity.tsv"))
    a = ap.parse_args()
    w = Writer(a.out, a.versions)
    if a.sonarjs:
        regen_sonarjs(w, a.sonarjs)
    if a.typescript_eslint:
        regen_tseslint(w, a.typescript_eslint)
    if a.eslint_js:
        regen_eslint_js(w, a.eslint_js)
    if a.next:
        regen_next(w, a.next)
    if a.jsx_a11y:
        regen_jsx_a11y(w, a.jsx_a11y)
    if a.prettier:
        regen_prettier(w, a.prettier)
    if a.ruff:
        regen_ruff(w, a.ruff)
    if a.sonar_meta:
        regen_sonar(w, a.table)


if __name__ == "__main__":
    main()

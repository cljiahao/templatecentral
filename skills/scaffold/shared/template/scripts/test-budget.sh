#!/usr/bin/env bash
# Test budget: test-budget.sh [-v] [project-dir]. Offline and read-only; plain text analysis, nothing installed.
# Enforces ADR-0001. Exit 0 within budget, 1 when the ratio is over the limit, 2 on bad input or an internal failure.
# Only one thing fails: test LOC per 100 source LOC above TEST_BUDGET_MAX_RATIO (default 35; set but empty is an error).
# Likely duplicates (a title repeated in one file or across files, near-identical assertion sets, a unit and an e2e
# file naming the same route or imported function) are reported and never fail; -v lists them, plus a count of
# test-file lines over 300 bytes. An unreadable file fails closed: exit 2 with one line naming it.
# Counting rules mirror the plugin's gate: a test file sits under test, tests or __tests__ or is named *.test.*, *.spec.*,
# test_*, *_test.py; source is code under src (any non-test code when the project has no src folder); a line counts
# when it is not blank and not a comment; one app per detected stack folder (root plus first-level folders).
# Limits: tests in folders that match none of those patterns (spec/, e2e/, cypress/ without a .test. or .spec.
# suffix) count as source or are ignored, as in the plugin's gate; size is counted by line, not by what a line holds.
# A symlink to a file is read through, as in the plugin's gate; a symlink to a folder is skipped.
set -uo pipefail
export LC_ALL=C

die() {
  printf 'test-budget: %s\n' "$1" >&2
  exit 2
}

VERBOSE=0
TARGET=
for arg in "$@"; do
  case "$arg" in
    -v | --verbose) VERBOSE=1 ;;
    -*) die "unknown option: $arg" ;;
    *) [ -z "$TARGET" ] || die "one project folder at most"; TARGET=$arg ;;
  esac
done
if [ -z "$TARGET" ]; then
  case "$0" in
    */*) TARGET=${0%/*}/.. ;;
    *) TARGET=.. ;;
  esac
fi
[ -d "$TARGET" ] || die "not a folder: $TARGET"
root=$(cd "$TARGET" 2> /dev/null && pwd) || die "cannot enter $TARGET"

LIMIT=${TEST_BUDGET_MAX_RATIO-35}
case "$LIMIT" in
  '' | . | *[!0-9.]* | *.*.*) die "TEST_BUDGET_MAX_RATIO must be a number (got '$LIMIT')" ;;
esac

for tool in awk mktemp rm tr sed grep find; do
  command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done

wd=
trap '[ -z "$wd" ] || rm -rf "$wd"' EXIT
wd=$(mktemp -d "${TMPDIR:-/tmp}/test-budget.XXXXXX") || die "cannot create a temporary folder (mktemp failed)"
[ -d "$wd" ] || die "cannot create a temporary folder (mktemp returned no folder)"

SKIP='node_modules .next dist build __pycache__ coverage .venv venv .git .turbo'

# Prints "stack kind" for a folder holding a known stack and returns 0; returns 1 otherwise.
detect() {
  local d=$1 f
  for f in "$d"/next.config.*; do
    [ -e "$f" ] && { echo "nextjs ts"; return 0; }
  done
  if [ -e "$d/nest-cli.json" ] || { [ -f "$d/package.json" ] && grep -q '@nestjs/core' "$d/package.json"; }; then
    echo "nestjs ts"
    return 0
  fi
  for f in "$d"/vite.config.*; do
    [ -e "$f" ] && { echo "vite-react ts"; return 0; }
  done
  for f in requirements.txt pyproject.toml requirements-dev.txt; do
    if [ -f "$d/$f" ] && grep -qi fastapi "$d/$f"; then
      echo "fastapi py"
      return 0
    fi
  done
  return 1
}

# Relative paths of the regular files of a folder (symlinks to files included), one per line, with backslash, tab
# and newline written as \\, \t and \n so every name stays on one line: tracked and untracked unignored files in a
# git work tree, else a walk. Names are read NUL-delimited.
listfiles() {
  local f
  if git -C "$1" ls-files -co --exclude-standard -z > "$wd/git.out" 2> /dev/null; then
    :
  else
    (cd "$1" && find . \( -name node_modules -o -name .next -o -name dist -o -name build -o -name __pycache__ \
      -o -name coverage -o -name .venv -o -name venv -o -name .git -o -name .turbo \) -prune -o \( -type f -o -type l \) -print0) > "$wd/git.out"
  fi
  while IFS= read -r -d '' f; do
    f=${f#./}
    [ -f "$1/$f" ] || continue
    f=${f//\\/\\\\}
    f=${f//$'\t'/\\t}
    printf '%s\n' "${f//$'\n'/\\n}"
  done < "$wd/git.out"
}

found=$wd/found
: > "$found"
if res=$(detect "$root"); then printf '%s\t%s\t%s\n' "$root" "${res% *}" "${res#* }" >> "$found"; fi
for d in "$root"/*/; do
  [ -d "$d" ] || continue
  d=${d%/}
  case " $SKIP " in *" ${d##*/} "*) continue ;; esac
  if res=$(detect "$d"); then printf '%s\t%s\t%s\n' "$d" "${res%% *}" "${res#* }" >> "$found"; fi
done
if [ ! -s "$found" ]; then
  listfiles "$root" > "$wd/rootlist"
  if grep -q '\.py$' "$wd/rootlist"; then kind=py; else kind=ts; fi
  printf '%s\tunknown\t%s\n' "$root" "$kind" >> "$found"
fi

apps=$wd/apps
list=$wd/list
: > "$apps"
: > "$list"
TAB=$(printf '\t')
while IFS="$TAB" read -r dir stack kind; do
  prefix=${dir#"$root"}
  prefix=${prefix#/}
  label=${prefix:-.}
  [ -z "$prefix" ] || prefix=$prefix/
  label="$stack ($label)"
  excl=
  while IFS="$TAB" read -r other _s _k; do
    case "$other" in "$dir"/*) excl="$excl${other#"$dir"/}$TAB" ;; esac
  done < "$found"
  printf '%s\t%s\n' "$label" "$kind" >> "$apps"
  listfiles "$dir" | sort | awk -v label="$label" -v kind="$kind" -v prefix="$prefix" -v excl="$excl" '
    BEGIN {
      n = split("node_modules .next dist build __pycache__ coverage .venv venv .git .turbo", S, " ")
      for (i = 1; i <= n; i++) SK[S[i]] = 1
      if (kind == "py") EX[".py"] = 1
      else { EX[".ts"] = 1; EX[".tsx"] = 1; EX[".js"] = 1; EX[".jsx"] = 1; EX[".mjs"] = 1; EX[".cjs"] = 1 }
      ne = split(excl, E, "\t")
    }
    {
      n = split($0, P, "/")
      for (i = 1; i < n; i++) if (P[i] in SK) next
      if (n >= 2 && P[1] == ".claude" && (P[2] == ".harness-base" || P[2] == "hooks")) next
      name = P[n]
      dot = 0
      for (i = length(name); i > 1; i--) if (substr(name, i, 1) == ".") { dot = i; break }
      if (!dot || !(substr(name, dot) in EX)) next
      for (i = 1; i <= ne; i++) if (E[i] != "" && index($0, E[i] "/") == 1) next
      print label "\t" prefix "\t" $0
    }' >> "$list"
done < "$found"

cat > "$wd/p.awk" << 'AWK'
function trim(s) {
  sub(/^[ \t\r]+/, "", s)
  sub(/[ \t\r]+$/, "", s)
  return s
}
function decode(s,   o, i, c, d) {
  o = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\") {
      d = substr(s, i + 1, 1)
      i++
      o = o (d == "n" ? "\n" : (d == "t" ? "\t" : d))
    } else o = o c
  }
  return o
}
function cnt(s, q,   n, i) {
  n = 0
  while ((i = index(s, q)) > 0) { n++; s = substr(s, i + length(q)) }
  return n
}
function gettitle(r,   c, i, n, t, ch) {
  sub(/^[ \t]+/, "", r)
  c = substr(r, 1, 1)
  if (c != "'" && c != "\"" && c != "`") return ""
  n = length(r)
  t = ""
  for (i = 2; i <= n; i++) {
    ch = substr(r, i, 1)
    if (ch == "\\") { t = t substr(r, i, 2); i++; continue }
    if (ch == c) return t
    t = t ch
  }
  return ""
}
function qualified(sep, title,   k, q) {
  q = ""
  for (k = 1; k <= nS; k++) q = q ST[k] sep
  return q title
}
function addset(arr, cntarr, f, key) {
  if (!((f, key) in arr)) { arr[f, key] = 1; cntarr[f]++; ord[f, cntarr[f]] = key }
}
function addtok(f, tok) {
  if (!((f, tok) in TK)) { TK[f, tok] = 1; nTK[f]++; TKL[f, nTK[f]] = tok }
}
function addnames(f, names,   m, i, W, nm) {
  gsub(/[(){}]/, " ", names)
  m = split(names, W, ",")
  for (i = 1; i <= m; i++) {
    nm = trim(W[i])
    sub(/^type[ \t]+/, "", nm)
    sub(/[ \t]+as[ \t]+.*$/, "", nm)
    if (nm ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && length(nm) >= 3) addtok(f, "fn:" nm)
  }
}
function note(kindrow, text) {
  if (kindrow == "B") { nB++; BR[nB] = text } else { nV++; VR[nV] = text }
}
BEGIN {
  CAP = 5
  nA = 0
  while ((getline rec < APPS) > 0) {
    split(rec, R, "\t")
    nA++
    AL[nA] = R[1]
    AK[nA] = R[2]
    AI[R[1]] = nA
  }
  nf = 0
  while ((getline rec < LIST) > 0) {
    split(rec, R, "\t")
    a = AI[R[1]]
    py = (AK[a] == "py")
    prefix = R[2]
    rel = R[3]
    disp = prefix rel
    full = ROOT "/" prefix decode(rel)
    nf++
    FA[nf] = a
    FD[nf] = disp
    n = split(rel, P, "/")
    name = P[n]
    D = "/"
    for (i = 1; i < n; i++) D = D P[i] "/"
    SD[nf] = (index(D, "/src/") > 0)
    if (SD[nf]) HS[a] = 1
    isT = (index(name, ".test.") || index(name, ".spec.") || substr(name, 1, 5) == "test_" \
      || (length(name) >= 8 && substr(name, length(name) - 7) == "_test.py") \
      || index(D, "/test/") || index(D, "/tests/") || index(D, "/__tests__/")) ? 1 : 0
    FT[nf] = isT
    lc = tolower(rel)
    FE[nf] = (index(lc, "e2e") || index(lc, "playwright") || index(lc, "cypress")) ? 1 : 0
    loc = 0; inb = 0; ind = 0; nl = 0; nS = 0
    split("", CF)
    while ((r = (getline line < full)) > 0) {
      nl++
      s = trim(line)
      if (s == "") continue
      isc = 0
      if (py) {
        if (ind) { isc = 1; if (index(s, "\"\"\"") || index(s, "'''")) ind = 0 }
        else if (substr(s, 1, 3) == "\"\"\"" || substr(s, 1, 3) == "'''") { isc = 1; if (cnt(s, substr(s, 1, 3)) < 2) ind = 1 }
        else if (substr(s, 1, 1) == "#" && substr(s, 1, 2) != "#!") isc = 1
      } else {
        if (inb) { isc = 1; if (index(s, "*/")) inb = 0 }
        else if (substr(s, 1, 2) == "/*") { isc = 1; if (!index(s, "*/")) inb = 1 }
        else if (substr(s, 1, 2) == "//") isc = 1
      }
      if (isc) continue
      loc++
      if (!isT) continue
      if (length(line) > 300) LL[a]++
      w = line
      sub(/^[ \t]+/, "", w)
      iw = length(line) - length(w)
      title = ""; tk = ""
      if (py) {
        if (match(s, /^(async[ \t]+)?(def|class)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
          m = split(substr(s, RSTART, RLENGTH), W, /[ \t]+/)
          if (W[1] == "async") { kw = W[2]; nm = W[3] } else { kw = W[1]; nm = W[2] }
          while (nS > 0 && SI[nS] >= iw) nS--
          if (kw == "class" && nm ~ /^Test/) { nS++; SI[nS] = iw; ST[nS] = nm }
          else if (kw == "def" && nm ~ /^test_/) { title = qualified(".", nm); tk = "t" }
        }
        if (s ~ /^assert[ \t(]/ || s ~ /self\.assert/ || s ~ /pytest\.raises/) { k = s; gsub(/[ \t]+/, "", k); addset(AS, nAS, nf, k) }
        if (match(s, /^from[ \t]+(src|\.)[A-Za-z0-9_.]*[ \t]+import[ \t]+/)) addnames(nf, substr(s, RSTART + RLENGTH))
      } else {
        if (match(s, /^(describe|context|suite)(\.(only|skip|concurrent|sequential|todo))*[ \t]*\(/)) {
          t = gettitle(substr(s, RLENGTH + 1))
          while (nS > 0 && SI[nS] >= iw) nS--
          nS++; SI[nS] = iw; ST[nS] = (t == "" ? "?" : t)
        } else if (match(s, /^(it|test)(\.(only|skip|concurrent|todo|fails|failing))*[ \t]*\(/)) {
          t = gettitle(substr(s, RLENGTH + 1))
          while (nS > 0 && SI[nS] >= iw) nS--
          if (t != "") { title = qualified(" > ", t); tk = "t" }
        }
        if (s ~ /expect[ \t]*\(/ || s ~ /assert[ \t]*[.(]/ || s ~ /\.should/) { k = s; gsub(/[ \t]+/, "", k); addset(AS, nAS, nf, k) }
        if (match(s, /^import[ \t]+(type[ \t]+)?\{[^}]*\}[ \t]*from[ \t]*["'](\.|@\/|~\/)/)) {
          h = substr(s, RSTART, RLENGTH)
          sub(/^[^{]*\{/, "", h)
          sub(/\}.*$/, "", h)
          addnames(nf, h)
        }
      }
      rest = s
      while (match(rest, /["'`]\/[A-Za-z0-9_][^"'` \t]*["'`]/)) {
        addtok(nf, "r:" substr(rest, RSTART + 1, RLENGTH - 2))
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (tk == "t") {
        if (title in CF) {
          DUPF[a]++
          note("V", disp ":" nl ": repeated test title in one file: \"" title "\" (first at line " CF[title] ")")
        } else {
          CF[title] = nl
          ttot[a]++
          if (!((a, title) in TFN)) { nTO[a]++; TO[a, nTO[a]] = title }
          TFN[a, title]++
          TFL[a, title] = (TFN[a, title] > 1 ? TFL[a, title] ", " : "") disp
        }
      }
    }
    close(full)
    if (r < 0) { nU++; if (UN == "") UN = disp; FA[nf] = 0 }
    FK[nf] = loc
  }
  for (a = 1; a <= nA; a++) {
    src = 0; tst = 0; tfiles = 0
    for (f = 1; f <= nf; f++) {
      if (FA[f] != a) continue
      if (FT[f]) { tst += FK[f]; tfiles++ }
      else if (SD[f] || !HS[a]) src += FK[f]
    }
    ratio = (src > 0) ? sprintf("%.2f", 100 * tst / src) : "n/a"
    if (src > 0 && tst * 100 > LIM * src) {
      nR++
      RR[nR] = AL[a] ": test LOC " tst " vs source LOC " src ": " ratio " per 100 source LOC, limit " LIM " (TEST_BUDGET_MAX_RATIO)"
    }
    nSame = DUPF[a] + 0
    for (j = 1; j <= nTO[a]; j++) {
      t = TO[a, j]
      if (TFN[a, t] > 1) { nSame++; if (nV < 400) note("V", "same title in " TFN[a, t] " files: \"" t "\": " TFL[a, t]) }
    }
    split("", INV); split("", ICN); split("", PC); split("", PL); nP = 0
    for (f = 1; f <= nf; f++) {
      if (FA[f] != a || !FT[f]) continue
      for (j = 1; j <= nAS[f]; j++) { k = ord[f, j]; ICN[k]++; INV[k] = INV[k] " " f }
    }
    for (k in INV) {
      if (ICN[k] < 2 || ICN[k] > CAP * 6) continue
      m = split(substr(INV[k], 2), W, " ")
      for (x = 1; x < m; x++) for (y = x + 1; y <= m; y++) {
        key = W[x] "," W[y]
        if (!(key in PC)) { nP++; PL[nP] = key }
        PC[key]++
      }
    }
    nSim = 0
    for (j = 1; j <= nP; j++) {
      split(PL[j], W, ",")
      n1 = nAS[W[1]]; n2 = nAS[W[2]]; sh = PC[PL[j]]
      if (n1 < 3 || n2 < 3) continue
      if (100 * sh >= 80 * (n1 + n2 - sh)) { nSim++; note("V", "near-identical assertions (" sh " of " n1 "/" n2 "): " FD[W[1]] ", " FD[W[2]]) }
    }
    split("", INV); split("", ICN); split("", PC); split("", PL); nP = 0
    for (f = 1; f <= nf; f++) {
      if (FA[f] != a || !FT[f]) continue
      for (j = 1; j <= nTK[f]; j++) { k = TKL[f, j]; ICN[k]++; INV[k] = INV[k] " " f }
    }
    nUE = 0
    for (k in INV) {
      if (ICN[k] < 2 || ICN[k] > CAP) continue
      m = split(substr(INV[k], 2), W, " ")
      for (x = 1; x < m; x++) for (y = x + 1; y <= m; y++) {
        if (FE[W[x]] == FE[W[y]]) continue
        key = W[x] "," W[y]
        if (key in PC) continue
        PC[key] = 1
        nUE++
        e = (FE[W[x]] ? W[x] : W[y]); u = (FE[W[x]] ? W[y] : W[x])
        note("V", "unit and e2e name the same " (substr(k, 1, 2) == "r:" ? "route" : "function") " " substr(k, (substr(k, 1, 2) == "r:" ? 3 : 4)) ": " FD[u] ", " FD[e])
      }
    }
    if (LL[a] > 0) note("V", AL[a] ": " LL[a] " test-file lines over 300 bytes (count only)")
    line = AL[a] ": src " src " LOC, test " tst " LOC, ratio " ratio " per 100 (limit " LIM "), " tfiles " test files; likely duplicates: " nSame " same-title, " nSim " similar-assertion, " nUE " unit-e2e"
    S[a] = line
    totDup += nSame + nSim + nUE
  }
  for (a = 1; a <= nA; a++) print "S\t" S[a]
  for (j = 1; j <= nR; j++) print "B\t" RR[j]
  for (j = 1; j <= nV; j++) print "V\t" VR[j]
  print "U\t" nU + 0 "\t" UN
  print "D\t" totDup + 0
}
AWK

if [ ! -s "$list" ]; then
  echo "test-budget: ok, no source or test files"
  exit 0
fi

awk -v APPS="$apps" -v LIST="$list" -v ROOT="$root" -v LIM="$LIMIT" -f "$wd/p.awk" > "$wd/result" || die "analysis failed"

summary=
dups=0
unreadable=0
unreadable_first=
nb=0
nv=0
: > "$wd/b"
: > "$wd/v"
while IFS="$TAB" read -r tag text; do
  case "$tag" in
    S) summary="${summary:+$summary | }$text" ;;
    B) printf '%s\n' "$text" >> "$wd/b"; nb=$((nb + 1)) ;;
    V) printf '%s\n' "$text" >> "$wd/v"; nv=$((nv + 1)) ;;
    D) dups=$text ;;
    U) unreadable=${text%%"$TAB"*}; unreadable_first=${text#*"$TAB"} ;;
  esac
done < "$wd/result"

if [ "$unreadable" -gt 0 ]; then
  more=
  [ "$unreadable" -eq 1 ] || more=" and $((unreadable - 1)) more"
  die "cannot read $unreadable_first$more (an unreadable file could hide a breach)"
fi

if [ "$nb" -gt 0 ]; then
  printf 'test-budget: FAIL, %s breach(es); fix per ADR-0001 (test each behaviour once)\n' "$nb"
  head -n 18 "$wd/b"
  [ "$nb" -le 18 ] || printf '... and %s more\n' "$((nb - 18))"
  exit 1
fi

if [ -z "$summary" ]; then
  echo "test-budget: ok, no source or test files"
  exit 0
fi
hint=
[ "$dups" -eq 0 ] || hint=" (-v lists them)"
printf 'test-budget: ok. %s%s\n' "$summary" "$hint"
if [ "$VERBOSE" -eq 1 ] && [ "$nv" -gt 0 ]; then
  head -n 20 "$wd/v"
  [ "$nv" -le 20 ] || printf '... and %s more\n' "$((nv - 20))"
fi
exit 0

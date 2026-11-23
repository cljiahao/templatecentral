# Scanner for check-exclude-reasons.sh and the migrate exclusion audit (the audit keeps a byte copy in exclusion-audit/scan.awk).
# Two modes. Default: reads one Sonar properties file. With -v mode=marks: reads source files for inline coverage markers.
# Usage: awk -v file=NAME -f check-exclude-reasons.awk NAME   (framework defaults come from TC_EXCLUDE_DEFAULTS, one per line)
#        awk -v mode=marks -f check-exclude-reasons.awk FILE...
# Output, tab separated: E file line kind entry status (status reason, none, shared or default); I file line kind entries status;
# X file line message for a setting the gate cannot read; M file line marker text status (status reason, none or file) for a marker.
# A reason is a "reason:" comment line in the comment block directly above the key. Its shape: at least 3 different words of 3+ letters,
# not a repeated single letter, not a path segment of the entry, and no placeholder (TC_REASON_PLACEHOLDERS, one per line). With one
# non-default entry any such line counts; with several, a reason must name the entry as a whole word and name no other entry of the list.
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function isplaceholder(w,   k) {
  w = tolower(w)
  for (k = 1; k <= nph; k++) if (ph[k] == w) return 1
  return 0
}
function setsegs(t,   n, a, i) {
  split("", segs)
  n = split(tolower(t), a, "[/*{}, !]+")
  for (i = 1; i <= n; i++) if (a[i] != "") segs[a[i]] = 1
}
function goodwords(t,   w, n, i, c, r, seen, l, f, x) {
  n = split(t, w, /[ \t,;"`()]+/)
  c = 0
  for (i = 1; i <= n; i++) {
    r = w[i]; sub(/[.:!?]+$/, "", r)
    if (r !~ /^[A-Za-z][A-Za-z'-]*$/) continue
    l = r; gsub(/[^A-Za-z]/, "", l)
    if (length(l) < 3) continue
    f = tolower(substr(l, 1, 1)); x = tolower(l); gsub(f, "", x)
    if (x == "") continue
    r = tolower(r)
    if ((r in segs) || (r in seen)) continue
    seen[r] = 1; c++
  }
  return c
}
function valid(t,   w, n, i, r) {
  if (t !~ /^reason:/) return 0
  sub(/^reason:/, "", t)
  t = trim(t)
  if (t == "") return 0
  n = split(t, w, /[ \t,;"`()]+/)
  for (i = 1; i <= n; i++) {
    r = w[i]; sub(/[.:!?]+$/, "", r)
    if (isplaceholder(r)) return 0
  }
  return (goodwords(t) >= 3)
}
function isdefault(e) { sub(/^!/, "", e); return (e in dflt) }
function lineat(off,   k, r) {
  r = segline[1]
  for (k = 1; k <= nseg; k++) if (segoff[k] <= off) r = segline[k]
  return r
}
function hits(t, e,   w, n, i, c, r) {
  n = split(t, w, /[ \t,;"`()]+/)
  c = 0
  for (i = 1; i <= n; i++) { r = w[i]; sub(/[.:]+$/, "", r); if (r == e) c++ }
  return c
}
function named(e,   k, j, t) {
  setsegs(e)
  for (k = 1; k <= nrs; k++) {
    if (!valid(rs[k])) continue
    t = rs[k]
    sub(/^reason:/, "", t)
    if (hits(t, e) == 0) continue
    for (j = 1; j <= nownlist; j++) if (ownlist[j] != e && hits(t, ownlist[j]) > 0) break
    if (j > nownlist) return 1
  }
  return 0
}
function anyvalid(entries,   k) {
  setsegs(entries)
  for (k = 1; k <= nrs; k++) if (valid(rs[k])) return 1
  return 0
}
function finish(   kind, scope, i, c, depth, tok, start, ent, nent, own, st, ln, e, tracked) {
  kind = ""
  tracked = (key ~ /sonar\./ && key ~ /([Ee]xclusion|[Ii]nclusion|[Ii]gnore)/)
  if (tracked) {
    if (key in seenkey) printf "X\t%s\t%d\tthe key %s is set twice in this file; the later value wins and a reason above one of them is not proof, so keep one\n", file, keyline, key
    seenkey[key] = 1
  }
  if (key ~ /(^|\.)sonar\.issue\.ignore\./) {
    if (key ~ /\.multicriteria$/ || key ~ /\.(ruleKey|fileRegexp|beginBlockRegexp|endBlockRegexp)$/) return
    printf "E\t%s\t%d\tsonar-issue-ignore\t%s\t%s\n", file, keyline, key "=" trim(val), (anyvalid(trim(val)) ? "reason" : "none")
    return
  }
  if (key ~ /(^|\.)sonar\.([A-Za-z0-9_-]+\.)*inclusions$/) kind = "include"
  else if (key ~ /(^|\.)sonar\.([A-Za-z0-9_-]+\.)*exclusions$/) {
    scope = substr(key, index(key, "sonar.") + 6)
    sub(/exclusions$/, "", scope)
    sub(/\.$/, "", scope)
    gsub(/\./, "-", scope)
    kind = (scope == "" ? "sonar-exclude" : "sonar-" scope "-exclude")
  } else {
    if (tracked) printf "X\t%s\t%d\t%s looks like an exclude setting, but the gate does not read it; use sonar.exclusions or sonar.coverage.exclusions so each entry can carry a reason\n", file, keyline, key
    return
  }
  nent = 0; depth = 0; tok = ""; start = 1
  for (i = 1; i <= length(val) + 1; i++) {
    c = substr(val, i, 1)
    if (c == "{" || c == "[") depth++
    if (c == "}" || c == "]") depth--
    if ((c == "," && depth <= 0) || i == length(val) + 1) {
      e = substr(val, start, i - start)
      ln = start
      while (substr(val, ln, 1) ~ /[ \t]/ && ln < i) ln++
      e = trim(e)
      if (e != "") { nent++; ent[nent] = e; entl[nent] = lineat(ln) }
      start = i + 1
    }
  }
  if (nent == 0) return
  if (kind == "include") {
    tok = ent[1]
    for (i = 2; i <= nent; i++) tok = tok ", " ent[i]
    printf "I\t%s\t%d\tcoverage-include\t%s\t%s\n", file, keyline, tok, (anyvalid(tok) ? "reason" : "none")
    return
  }
  own = 0; nownlist = 0; tok = ""
  for (i = 1; i <= nent; i++) if (!isdefault(ent[i])) { own++; ownlist[++nownlist] = ent[i]; tok = tok " " ent[i] }
  for (i = 1; i <= nent; i++) {
    if (isdefault(ent[i])) st = "default"
    else if (own == 1) st = (anyvalid(tok) ? "reason" : "none")
    else st = (named(ent[i]) ? "reason" : "none")
    printf "E\t%s\t%d\t%s\t%s\t%s\n", file, entl[i], kind, ent[i], st
  }
}
# Inline coverage markers in source files: a marker needs a "reason:" on the same line or the line above. A whole-file marker never passes.
function reasontext(t,   i) {
  i = index(tolower(t), "reason:")
  if (i == 0) return ""
  t = substr(t, i)
  sub(/[ \t]*\*\/.*$/, "", t)
  return trim(t)
}
function markline(raw, nr,   low, js, kind, prevt, st, at) {
  low = tolower(raw)
  kind = ""
  js = (FILENAME ~ /\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|vue|svelte)$/)
  if (js) {
    if (match(low, /(\/\*|\/\/).*(istanbul|c8|v8)[ \t]+ignore[ \t]+(file|next|if|else|start)/) || match(low, /(\/\*|\/\/).*node:coverage[ \t]+(ignore|disable)/)) kind = substr(low, RSTART, RLENGTH)
  } else if (match(low, /#[ \t]*pragma[: \t]*no[ \t]*(cover|branch)/)) kind = substr(low, RSTART, RLENGTH)
  if (kind == "") return
  if (match(kind, /(istanbul|c8|v8|node:coverage)[ \t]+(ignore|disable).*/)) kind = substr(kind, RSTART)
  setsegs("")
  at = raw
  sub(/\r$/, "", at)
  st = (valid(reasontext(at)) ? "reason" : "none")
  if (st == "none") {
    prevt = prev
    sub(/^[ \t]*(\/\/+|#+|\/\*+|\*+)[ \t]*/, "", prevt)
    if (valid(reasontext(prevt))) st = "reason"
  }
  if (kind ~ /ignore[ \t]+file/) st = "file"
  f = FILENAME
  sub(/^\.\//, "", f)
  at = trim(at)
  if (length(at) > 100) at = substr(at, 1, 100)
  printf "M\t%s\t%d\t%s\t%s\t%s\n", f, nr, trim(kind), at, st
}
BEGIN {
  marks = (mode == "marks")
  n = split(ENVIRON["TC_EXCLUDE_DEFAULTS"], d, "\n")
  for (k = 1; k <= n; k++) dflt[d[k]] = 1
  nblk = 0; incont = 0; prev = ""
  nph = split(ENVIRON["TC_REASON_PLACEHOLDERS"], ph, "\n")
}
marks {
  if (FNR == 1) prev = ""
  markline($0, FNR)
  prev = $0
  next
}
{
  raw = $0
  sub(/\r$/, "", raw)
  if (NR == 1) sub("^\357\273\277", "", raw)
  if (!incont) {
    t = raw
    sub(/^[ \t]+/, "", t)
    if (t == "") { nblk = 0; next }
    if (substr(t, 1, 1) == "#" || substr(t, 1, 1) == "!") { blk[++nblk] = trim(substr(t, 2)); next }
    nrs = nblk
    for (k = 1; k <= nblk; k++) rs[k] = blk[k]
    nblk = 0
    keyline = NR
    match(t, /[=: \t]/)
    if (RSTART == 0) { key = t; rest = "" } else { key = substr(t, 1, RSTART - 1); rest = substr(t, RSTART) }
    sub(/^[ \t]*[=:]?[ \t]*/, "", rest)
    val = ""; nseg = 0
    text = rest
  } else {
    text = raw
    sub(/^[ \t]+/, "", text)
  }
  m = match(text, /\\+$/)
  cont = 0
  if (m > 0 && ((length(text) - m + 1) % 2 == 1)) { cont = 1; text = substr(text, 1, length(text) - 1) }
  nseg++
  segoff[nseg] = length(val) + 1
  segline[nseg] = NR
  val = val text
  if (cont) { incont = 1; next }
  incont = 0
  finish()
}
END { if (!marks && incont) finish() }

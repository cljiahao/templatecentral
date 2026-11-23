# Scanner for check-exclude-reasons.sh: reads one sonar-project.properties file.
# Usage: awk -v file=NAME -f check-exclude-reasons.awk NAME   (framework defaults come from TC_EXCLUDE_DEFAULTS, one per line)
# Output, tab separated: E file line kind entry status (status reason, none or default); I file line kind entries status.
# A reason is a "reason:" comment line with at least 3 distinct words of 3+ letters and no placeholder word (TC_REASON_PLACEHOLDERS,
# one per line), in the comment block directly above the key. With one non-default entry any such line counts; with
# several, a reason must name the entry as a whole word and name no other entry of the list: one reason, one entry.
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function isplaceholder(w,   k) {
  w = tolower(w)
  for (k = 1; k <= nph; k++) if (ph[k] == w) return 1
  return 0
}
function words(t, w,   n, i, c, seen, u) {
  n = split(t, w, /[ \t,;"`()]+/)
  c = 0
  for (i = 1; i <= n; i++) {
    sub(/[.:]+$/, "", w[i])
    if (length(w[i]) >= 3 && !(tolower(w[i]) in seen)) { seen[tolower(w[i])] = 1; c++ }
  }
  return c
}
function valid(t,   w, n, i, c, r) {
  if (t !~ /^reason:/) return 0
  sub(/^reason:/, "", t)
  t = trim(t)
  if (t == "") return 0
  n = split(t, w, /[ \t,;"`()]+/)
  for (i = 1; i <= n; i++) {
    r = w[i]; sub(/[.:]+$/, "", r)
    if (isplaceholder(r)) return 0
  }
  return (words(t, w) >= 3)
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
function anyvalid(   k) {
  for (k = 1; k <= nrs; k++) if (valid(rs[k])) return 1
  return 0
}
function finish(   kind, parts, np, i, c, depth, tok, start, entries, ent, nent, own, st, ln, e) {
  kind = ""
  if (key ~ /(^|\.)sonar\.exclusions$/) kind = "sonar-exclude"
  else if (key ~ /(^|\.)sonar\.coverage\.exclusions$/) kind = "sonar-coverage-exclude"
  else if (key ~ /(^|\.)sonar\.cpd\.exclusions$/) kind = "sonar-cpd-exclude"
  else if (key ~ /(^|\.)sonar\.test\.exclusions$/) kind = "sonar-test-exclude"
  else if (key ~ /(^|\.)sonar\.inclusions$/ || key ~ /(^|\.)sonar\.coverage\.inclusions$/) kind = "include"
  else if (key ~ /(^|\.)sonar\.issue\.ignore\./) {
    if (key ~ /\.multicriteria$/ || key ~ /\.(ruleKey|fileRegexp|beginBlockRegexp|endBlockRegexp)$/) return
    printf "E\t%s\t%d\tsonar-issue-ignore\t%s\t%s\n", file, keyline, key "=" trim(val), (anyvalid() ? "reason" : "none")
    return
  } else return
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
    printf "I\t%s\t%d\tcoverage-include\t%s\t%s\n", file, keyline, tok, (anyvalid() ? "reason" : "none")
    return
  }
  own = 0; nownlist = 0
  for (i = 1; i <= nent; i++) if (!isdefault(ent[i])) { own++; ownlist[++nownlist] = ent[i] }
  for (i = 1; i <= nent; i++) {
    if (isdefault(ent[i])) st = "default"
    else if (own == 1) st = (anyvalid() ? "reason" : "none")
    else st = (named(ent[i]) ? "reason" : "none")
    printf "E\t%s\t%d\t%s\t%s\t%s\n", file, entl[i], kind, ent[i], st
  }
}
BEGIN {
  n = split(ENVIRON["TC_EXCLUDE_DEFAULTS"], d, "\n")
  for (k = 1; k <= n; k++) dflt[d[k]] = 1
  nblk = 0; incont = 0
  nph = split(ENVIRON["TC_REASON_PLACEHOLDERS"], ph, "\n")
}
{
  raw = $0
  sub(/\r$/, "", raw)
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
END { if (incont) finish() }

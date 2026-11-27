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
# Reduce an entry to a plain pattern, as norm_pat in check-exclude-rules.sh does.
function norm(p) {
  sub(/^!/, "", p); sub(/^\^/, "", p); sub(/\$$/, "", p)
  gsub(/\\\./, ".", p)
  gsub(/\.\*/, "*", p)
  while (index(p, "//") > 0 || index(p, "/./") > 0) { gsub(/\/\//, "/", p); gsub(/\/\.\//, "/", p) }
  while (p ~ /^\.\// || p ~ /^\//) sub(/^\.?\//, "", p)
  if (p == ".") p = ""
  sub(/\/$/, "", p)
  return p
}
function isdefault(e) { e = norm(e); return (e != "" && (e in dflt)) }
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
  if (key ~ /(^|\.)sonar\.([A-Za-z0-9_-]+\.)*test\.inclusions$/) return
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
# Inline markers in source files: a coverage marker counts only as the first token of a comment (a marker inside a string, or later in
# a comment sentence, is not one); NOSONAR counts anywhere in a comment, as an upper-case whole word. Each needs a "reason:" on the same line or the line above. An
# ignore-file marker never passes, and neither does a v8 or c8 "ignore start", or a Stryker "disable", with no "ignore stop" or
# a "restore" naming the same mutators (or "restore all") after it in the file (it covers the rest of the file).
function reasontext(t,   i) {
  i = index(tolower(t), "reason:")
  if (i == 0) return ""
  t = substr(t, i)
  sub(/[ \t]*\*\/.*$/, "", t)
  return trim(t)
}
# The mutator list of a Stryker disable or restore: a sorted set of lower case names, "all" when none is named or "all" is one of them.
# A name with a space in it, or an empty name, is free text, not a mutator: the list reads "?", which a disable keeps open until restore all.
function mlist(s,   n, p, i, j, t, out) {
  sub(/^stryker[ \t]+(disable|restore)/, "", s)
  sub(/[ \t]+--.*$/, "", s)
  sub(/[ \t]*reason[ \t]*:.*$/, "", s)
  sub(/:.*$/, "", s)
  gsub(/[ \t]*,[ \t]*/, ",", s)
  s = trim(s)
  if (s == "") return "all"
  n = split(s, p, ",")
  for (i = 1; i <= n; i++) if (p[i] ~ /[ \t]/ || p[i] == "") return "?"
  for (i = 1; i <= n; i++) if (p[i] == "all") return "all"
  for (i = 2; i <= n; i++) {
    t = p[i]
    for (j = i - 1; j >= 1 && p[j] > t; j--) p[j + 1] = p[j]
    p[j + 1] = t
  }
  out = ""
  for (i = 1; i <= n; i++) if (i == 1 || p[i] != p[i - 1]) out = out (out == "" ? "" : ",") p[i]
  return out
}
function popat(k,   j) {
  for (j = k; j < nstack; j++) { stack[j] = stack[j + 1]; smut[j] = smut[j + 1] }
  nstack--
}
function cm(body, nr, raw, own,   low, kind, st, prevt, at, rest, big, nn, k, ml, hit) {
  # A reason in a later comment on the line of a marker still counts, as in /* Stryker disable all */ // reason: why.
  if (nrec > 0 && rline[nrec] == nr && rst[nrec] == "none" && valid(reasontext(body))) rst[nrec] = "reason"
  low = tolower(body)
  sub(/^[ \t*]+/, "", low)
  kind = ""; big = 0
  if (isjs) {
    if (match(low, /^(istanbul|c8|v8)[ \t]+ignore[ \t]+(file|next|if|else|start|stop)/) || match(low, /^node:coverage[ \t]+(ignore|disable)/)) kind = substr(low, RSTART, RLENGTH)
    else if (match(low, /^stryker[ \t]+disable[ \t]+next-line/)) kind = "stryker disable next-line"
    else if (match(low, /^stryker[ \t]+disable([ \t]|$)/)) kind = "stryker disable"
    else if (match(low, /^stryker[ \t]+restore([ \t]|$)/)) kind = "stryker restore"
  } else if (match(low, /^pragma[: \t]*no[ \t]*(cover|branch)/)) kind = "# " substr(low, RSTART, RLENGTH)
  # NOSONAR suppresses wherever it stands in a comment, so the word counts anywhere in the comment text (tested once per comment).
  if (kind == "" && body == own && match(" " own " ", /[^A-Za-z0-9_]NOSONAR[^A-Za-z0-9_]/)) kind = "nosonar"
  if (kind == "") return
  if (kind ~ /ignore[ \t]+stop$/) {
    for (k = nstack; k >= 1; k--) if (smut[k] == "") { popat(k); break }
    return
  }
  # A restore closes only the disable whose mutator list it names; "restore all" closes every open disable.
  if (kind == "stryker restore") {
    ml = mlist(low)
    hit = 0
    for (k = nstack; k >= 1; k--) if (smut[k] != "" && (ml == "all" || ml == smut[k])) { popat(k); hit = 1; if (ml != "all") break }
    # A restore that closes no open disable is a finding: the mutators it names were never disabled, or were already restored.
    if (!hit) {
      at = trim(raw)
      sub(/\r$/, "", at)
      if (length(at) > 100) at = substr(at, 1, 100)
      nrec++
      rline[nrec] = nr; rkind[nrec] = kind; rtext[nrec] = at; rst[nrec] = "unmatched"
    }
    return
  }
  # ignore next N with N above 20 covers a block, not a line: it reads like an ignore start with no stop.
  if (kind ~ /ignore[ \t]+next$/) {
    rest = substr(low, length(kind) + 1)
    if (match(rest, /^[ \t]+[0-9]+/)) { nn = substr(rest, RSTART, RLENGTH) + 0; if (nn > 20) big = 1 }
  }
  setsegs("")
  at = raw
  sub(/\r$/, "", at)
  # The reason comes from the marker's own comment, or from a comment-only line above it; never from code or a string on the line.
  st = (valid(reasontext(own)) ? "reason" : "none")
  if (st == "none" && prev ~ /^[ \t]*(\/\/+|#+|\/\*+|\*+)/) {
    prevt = prev
    sub(/^[ \t]*(\/\/+|#+|\/\*+|\*+)[ \t]*/, "", prevt)
    if (valid(reasontext(prevt))) st = "reason"
  }
  if (kind ~ /ignore[ \t]+file$/ || big) st = "file"
  at = trim(at)
  if (length(at) > 100) at = substr(at, 1, 100)
  nrec++
  rline[nrec] = nr; rkind[nrec] = kind; rtext[nrec] = at; rst[nrec] = st
  if (kind ~ /ignore[ \t]+start$/ || kind == "stryker disable") { stack[++nstack] = nrec; smut[nstack] = (kind == "stryker disable" ? mlist(low) : ""); if (smut[nstack] == "?") smut[nstack] = "all" }
}
function flush(   k, f) {
  if (fname == "") return
  for (k = 1; k <= nstack; k++) rst[stack[k]] = "file"
  f = fname
  sub(/^\.\//, "", f)
  for (k = 1; k <= nrec; k++) printf "M\t%s\t%d\t%s\t%s\t%s\n", f, rline[k], rkind[k], rtext[k], rst[k]
  nrec = 0; nstack = 0
}
# Walk one line outside strings: call cm() with the text after each comment opener.
# A JS "/" starts a regular expression literal when the token before it cannot end a value; a quote inside one is not a string.
function rxok() {
  if (lastsig == "") return 1
  if (lastsig == "a") return (index(" return typeof case in of delete void throw new else do yield await instanceof ", " " lastword " ") > 0)
  return (index("(,=:[!&|?{;+-*%>~^", lastsig) > 0)
}
function rxend(raw, i, n,   j, c, incls) {
  j = i + 1; incls = 0
  while (j <= n) {
    c = substr(raw, j, 1)
    if (c == "\\") { j += 2; continue }
    if (incls) { if (c == "]") incls = 0 }
    else if (c == "[") incls = 1
    else if (c == "/") {
      j++
      while (substr(raw, j, 1) ~ /[A-Za-z]/) j++
      return j - 1
    }
    j++
  }
  return 0
}
function lex(raw, nr,   i, n, c, d, two, rest, j, q, blank, own) {
  n = length(raw); i = 1
  lastsig = ""; lastword = ""
  while (i <= n) {
    if (inblock) {
      j = index(substr(raw, i), "*/")
      rest = (j > 0 ? substr(raw, i, j - 1) : substr(raw, i))
      if (pendfirst && rest !~ /^[ \t*]*$/) { cm(rest, nr, raw, rest); pendfirst = 0 }
      if (j == 0) return
      inblock = 0; pendfirst = 0
      i += j + 1
      lastsig = ""; lastword = ""
      continue
    }
    if (tq != "") {
      j = index(substr(raw, i), tq)
      if (j == 0) return
      i += j + 2; tq = ""
      continue
    }
    if (bt) {
      c = substr(raw, i, 1)
      if (c == "\\") { i += 2; continue }
      if (c == "`") { bt = 0; lastsig = "a"; lastword = "" }
      i++
      continue
    }
    c = substr(raw, i, 1); two = substr(raw, i, 2)
    if (isjs) {
      if (two == "//") { own = substr(raw, i + 2); cm(own, nr, raw, own); return }
      if (two == "/*") {
        j = index(substr(raw, i + 2), "*/")
        rest = (j > 0 ? substr(raw, i + 2, j - 1) : substr(raw, i + 2))
        blank = (rest ~ /^[ \t*]*$/)
        if (!blank) cm(rest, nr, raw, rest)
        if (j > 0) { i += j + 3; continue }
        inblock = 1; pendfirst = blank
        return
      }
      if (c == "`") { bt = 1; i++; continue }
    } else {
      if (c == "#") {
        # Every # segment of the comment is tested: x = 1  # noqa  # pragma: no cover
        own = substr(raw, i + 1); rest = own
        while (1) {
          cm(rest, nr, raw, own)
          j = index(rest, "#")
          if (j == 0) break
          rest = substr(rest, j + 1)
        }
        return
      }
      q = substr(raw, i, 3)
      if (q == "\042\042\042" || q == "\047\047\047") { tq = q; i += 3; continue }
    }
    if (c == "\042" || c == "\047") {
      i++
      while (i <= n) {
        d = substr(raw, i, 1)
        if (d == "\\") { i += 2; continue }
        if (d == c) break
        i++
      }
      i++
      lastsig = "a"; lastword = ""
      continue
    }
    if (isjs && c == "/") {
      if (rxok()) {
        j = rxend(raw, i, n)
        if (j > 0) { i = j + 1; lastsig = "a"; lastword = ""; continue }
      }
      lastsig = c; lastword = ""; i++
      continue
    }
    if (c ~ /[A-Za-z0-9_$]/) {
      match(substr(raw, i), /^[A-Za-z0-9_$]+/)
      lastword = substr(raw, i, RLENGTH); lastsig = "a"
      i += RLENGTH
      continue
    }
    if (c != " " && c != "\t") { lastsig = c; lastword = "" }
    i++
  }
}
function markline(raw, nr) { lex(raw, nr) }
BEGIN {
  marks = (mode == "marks")
  n = split(ENVIRON["TC_EXCLUDE_DEFAULTS"], d, "\n")
  for (k = 1; k <= n; k++) dflt[norm(d[k])] = 1
  nblk = 0; incont = 0; prev = ""
  nph = split(ENVIRON["TC_REASON_PLACEHOLDERS"], ph, "\n")
}
marks {
  if (FNR == 1) {
    flush()
    prev = ""; inblock = 0; pendfirst = 0; tq = ""; bt = 0
    fname = FILENAME
    isjs = (FILENAME ~ /\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|vue|svelte)$/)
  }
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
END { if (marks) flush(); else if (incont) finish() }

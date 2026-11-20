#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984: the cached connect promise is reset when the connect fails.
# The older client awaits the cached promise with no reset, so one failed connect fails every later request.
# Matches when an awaited X.promise has no reset of X.promise (to null or undefined, delete X.promise, or X = { promise: null }) in the catch
# block of a try that contains the await, or inside a .catch(...) call. A reset in finally, or in a catch of an unrelated try, does not count.
# Files are found by content (a mongoose.connect( call), not by file name. Known limits: only the shape "await X.promise" is read, not "const p = X.promise; await p", Promise.all([...]) or a dotted receiver;
# regex literals and braces inside template literals are not parsed. A false match is possible when the reset is made by a helper.
export id=mongoose-client-promise-retry
export level=high
export names="*.ts *.js *.mjs *.cjs"
export content="mongoose.connect("
export template=skills/add/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts
export desc="the Mongoose client awaits a cached connect promise and never resets it in a catch after a failure, so one failed connect fails every later request; a reset only in finally is a different pattern and still matches"
export fix="wrap the await in try/catch, set cached.promise = null in the catch, and rethrow"

# Print FILE:LINE of the first awaited X.promise that has no reset in a matching catch. Reads comment-stripped text as tokens in one pass.
check() {
  local text n
  text=$(strip_comments "$1") || return 1
  n=$(printf '%s\n' "$text" | LC_ALL=C awk '
    function isidc(c) { return c ~ /[A-Za-z0-9_$]/ }
    function isidt(t) { return t ~ /^[A-Za-z_$]/ }
    function emit(t) { nt++; tok[nt] = t; tl[nt] = NR }
    function closer(k, op, cl,   d, m) {
      d = 0
      for (m = k; m <= nt; m++) {
        if (tok[m] == op) d++
        else if (tok[m] == cl) { d--; if (d == 0) return m }
      }
      return nt
    }
    function reset(w,   s) {
      if (cur <= callend) resetany[w] = 1
      for (s = 1; s <= sp; s++) if (fk[s] == "catch") resettry[w SUBSEP fid[s]] = 1
    }
    {
      len = length($0); i = 1
      while (i <= len) {
        c = substr($0, i, 1)
        if (instr != "") {
          if (c == "\\") { i += 2; continue }
          if (c == instr) { instr = ""; emit("STR") }
          i++
          continue
        }
        if (c == " " || c == "\t" || c == "\r") { i++; continue }
        if (c == "\"" || c == "\047" || c == "`") { instr = c; i++; continue }
        if (isidc(c)) {
          j = i + 1
          while (j <= len && isidc(substr($0, j, 1))) j++
          emit(substr($0, i, j - i))
          i = j
          continue
        }
        three = substr($0, i, 3); two = substr($0, i, 2)
        if (three == "===" || three == "!==") { emit("=="); i += 3; continue }
        if (two == "==" || two == "!=") { emit("=="); i += 2; continue }
        if (two == "=>") { emit("=>"); i += 2; continue }
        emit(c)
        i++
      }
      if (instr != "`") instr = ""
    }
    END {
      for (cur = 1; cur <= nt; cur++) {
        t = tok[cur]; cpt = pt; pt = 0
        if (t == "{") {
          sp++
          if (bk[cur] == "try") { fk[sp] = "try"; fid[sp] = ++tid }
          else if (bk[cur] == "catch") { fk[sp] = "catch"; fid[sp] = btry[cur] }
          else { fk[sp] = "b"; fid[sp] = 0 }
          continue
        }
        if (t == "}") {
          if (sp > 0) { if (fk[sp] == "try") pt = fid[sp]; sp-- }
          continue
        }
        if (t == "try") { if (tok[cur + 1] == "{") bk[cur + 1] = "try"; continue }
        if (t == "catch") {
          if (cur > 1 && tok[cur - 1] == ".") {
            if (tok[cur + 1] == "(") { e = closer(cur + 1, "(", ")"); if (e > callend) callend = e }
          } else {
            j = cur + 1
            if (tok[j] == "(") j = closer(j, "(", ")") + 1
            if (tok[j] == "{") { bk[j] = "catch"; btry[j] = cpt }
            cur = j - 1
          }
          continue
        }
        if (t == "await") {
          k = cur + 1
          while (tok[k] == "(") k++
          if (isidt(tok[k]) && tok[k + 1] == "." && tok[k + 2] == "promise") {
            na++; aw[na] = tok[k]; aln[na] = tl[cur]; tr = ""
            for (s = 1; s <= sp; s++) if (fk[s] == "try") tr = tr "|" fid[s] "|"
            atr[na] = tr
          }
          continue
        }
        if (t == "delete" && tok[cur + 2] == "." && tok[cur + 3] == "promise") { reset(tok[cur + 1]); continue }
        if (isidt(t) && tok[cur - 1] != ".") {
          if (tok[cur + 1] == "." && tok[cur + 2] == "promise" && tok[cur + 3] == "=" && (tok[cur + 4] == "null" || tok[cur + 4] == "undefined")) reset(t)
          else if (tok[cur + 1] == "=" && tok[cur + 2] == "{" && tok[cur - 1] != "const" && tok[cur - 1] != "let" && tok[cur - 1] != "var") {
            e = closer(cur + 2, "{", "}")
            for (m = cur + 3; m < e; m++) if (tok[m] == "promise" && tok[m + 1] == ":" && (tok[m + 2] == "null" || tok[m + 2] == "undefined")) { reset(t); break }
          }
        }
      }
      for (a = 1; a <= na; a++) {
        w = aw[a]
        if (w in resetany) continue
        ok = 0
        np = split(atr[a], parts, "|")
        for (p = 1; p <= np; p++) if (parts[p] != "" && ((w SUBSEP parts[p]) in resettry)) ok = 1
        if (!ok) { print aln[a]; exit }
      }
    }') || return 1
  if [ -n "$n" ]; then echo "$1:$n"; fi
}

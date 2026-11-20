#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984: the cached connect promise is reset when the connect fails.
# The older client awaits the cached promise with no reset, so one failed connect fails every later request.
export id=mongoose-client-promise-retry
export level=high
export names="mongoose-client.ts"
export template=skills/add/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts
export desc="the Mongoose client awaits a cached connect promise and never resets it after a failure, so one failed connect fails every later request"
export fix="wrap the await in try/catch, set cached.promise = null in the catch, and rethrow"

# Match a client that awaits X.promise and never sets X.promise to null or undefined inside a catch block. Works on comment-stripped text.
# A reset in another function's catch block still counts as a reset, and a .catch(() => X.promise = null) with no braces does not.
check() {
  local text n
  text=$(strip_comments "$1") || return 1
  n=$(printf '%s\n' "$text" | awk '
    function isid(ch) { return ch != "" && index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$", ch) > 0 }
    function isws(ch) { return ch != "" && index(" \t\n(", ch) > 0 }
    function isbl(ch) { return ch != "" && index(" \t\n", ch) > 0 }
    { s = s $0 "\n" }
    END {
      n = length(s); line = 1; depth = 0; nc = 0; pend = 0; na = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\n") { line++; continue }
        if (c == "{") { depth++; if (pend) { nc++; cd[nc] = depth; pend = 0 } continue }
        if (c == "}") { if (nc > 0 && cd[nc] == depth) nc--; depth--; continue }
        if (!isid(c) || isid(substr(s, i - 1, 1))) continue
        j = i
        while (isid(substr(s, j, 1))) j++
        w = substr(s, i, j - i)
        if (w == "catch") { pend = 1; continue }
        if (w == "await") {
          k = j
          while (isws(substr(s, k, 1))) k++
          m = k
          while (isid(substr(s, m, 1))) m++
          if (m > k && substr(s, m, 8) == ".promise" && !isid(substr(s, m + 8, 1))) { na++; aid[na] = substr(s, k, m - k); aln[na] = line }
          continue
        }
        if (substr(s, j, 8) == ".promise" && !isid(substr(s, j + 8, 1)) && substr(s, i - 1, 1) != ".") {
          k = j + 8
          while (isbl(substr(s, k, 1))) k++
          if (substr(s, k, 1) == "=" && substr(s, k + 1, 1) != "=") {
            k++
            while (isbl(substr(s, k, 1))) k++
            m = k
            while (isid(substr(s, m, 1))) m++
            v = substr(s, k, m - k)
            if ((v == "null" || v == "undefined") && nc > 0) reset[w] = 1
          }
        }
      }
      for (a = 1; a <= na; a++) if (!(aid[a] in reset)) { print aln[a]; exit }
    }') || return 1
  if [ -n "$n" ]; then echo "$1:$n"; fi
}

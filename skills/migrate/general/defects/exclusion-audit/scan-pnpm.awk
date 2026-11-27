# Scanner for exclusion-audit.sh: lists minimumReleaseAgeExclude entries of pnpm-workspace.yaml, .npmrc and package.json.
# Usage: awk -v file=NAME -v mode=yaml|npmrc|json -f scan-pnpm.awk NAME
# Output, tab separated: P file line entry status. Status is reason when a "reason:" comment with at least 3 words sits on the
# line directly above the entry (or above the key when the setting has one entry), none otherwise, nojson in package.json.
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function unquote(s) { s = trim(s); gsub(/^["']|["',]+$/, "", s); return s }
function valid(t,   w, n) {
  t = trim(t)
  sub(/^[#;][ \t]*/, "", t)
  if (t !~ /^reason:/) return 0
  sub(/^reason:/, "", t)
  t = trim(t)
  n = split(t, w, /[ \t]+/)
  return (t != "" && n >= 3)
}
function add(text, ln) { n++; ent[n] = unquote(text); entl[n] = ln }
function flush(   i, st) {
  for (i = 1; i <= n; i++) {
    if (mode == "json") st = "nojson"
    else st = (valid(prev[entl[i] - 1]) || (n == 1 && valid(prev[keyline - 1]))) ? "reason" : "none"
    printf "P\t%s\t%d\t%s\t%s\n", file, entl[i], ent[i], st
  }
  if (n == 0 && keyline > 0) printf "P\t%s\t%d\t(setting present, no entry read)\t%s\n", file, keyline, (mode == "json" ? "nojson" : (valid(prev[keyline - 1]) ? "reason" : "none"))
  n = 0; keyline = 0; inlist = 0
}
{
  line = $0
  sub(/\r$/, "", line)
  prev[NR] = line
  t = trim(line)
  if (mode == "yaml") {
    if (inlist && (t == "" || t ~ /^#/)) next
    if (inlist && line ~ /^[ \t]+-/) { sub(/^[ \t]+-[ \t]*/, "", line); sub(/[ \t]+#.*$/, "", line); add(line, NR); next }
    if (inlist) flush()
    if (line ~ /^["']?minimumReleaseAgeExclude["']?[ \t]*:/) {
      keyline = NR
      v = line
      sub(/^[^:]*:[ \t]*/, "", v)
      sub(/[ \t]+#.*$/, "", v)
      if (v ~ /^\[/) {
        gsub(/^\[|\][ \t]*$/, "", v)
        m = split(v, parts, ",")
        for (i = 1; i <= m; i++) if (trim(parts[i]) != "") add(parts[i], NR)
        flush()
      } else inlist = 1
    }
  } else if (mode == "npmrc") {
    if (t ~ /^minimum-release-age-exclude(\[\])?[ \t]*=/ || t ~ /^minimumReleaseAgeExclude(\[\])?[ \t]*=/) {
      v = t
      sub(/^[^=]*=[ \t]*/, "", v)
      keyline = NR
      m = split(v, parts, ",")
      for (i = 1; i <= m; i++) if (trim(parts[i]) != "") add(parts[i], NR)
      flush()
    }
  } else {
    if (injs && t ~ /\]/) { sub(/\].*$/, "", t); if (t != "") { m = split(t, parts, ","); for (i = 1; i <= m; i++) if (trim(parts[i]) != "") add(parts[i], NR) } flush(); injs = 0; next }
    if (injs) { m = split(t, parts, ","); for (i = 1; i <= m; i++) if (trim(parts[i]) != "") add(parts[i], NR); next }
    if (t ~ /^"minimumReleaseAgeExclude"[ \t]*:/) {
      keyline = NR
      v = t
      sub(/^[^:]*:[ \t]*/, "", v)
      sub(/^\[/, "", v)
      if (v ~ /\]/) { sub(/\].*$/, "", v); m = split(v, parts, ","); for (i = 1; i <= m; i++) if (trim(parts[i]) != "") add(parts[i], NR); flush() }
      else { if (trim(v) != "") { m = split(v, parts, ","); for (i = 1; i <= m; i++) if (trim(parts[i]) != "") add(parts[i], NR) } injs = 1 }
    }
  }
}
END { if (inlist || injs) flush() }

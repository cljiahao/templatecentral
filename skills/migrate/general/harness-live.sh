#!/usr/bin/env bash
# Harness live check: prove the seeded harness is wired and fires in a project, not only present. It never writes to the project.
# Usage: harness-live.sh <project-dir>
# Prints PASS or FAIL per item; exits 1 when any item fails, 2 on a usage error. It reads no environment or key file.
# Needs bash 3.2+, git, and python3 or node to read .claude/settings.json.
set -u

[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: harness-live.sh <project-dir>" >&2; exit 2; }
P=$(cd "$1" && pwd -P) || exit 2

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a tool from the project first, then PATH.
resolve() {
  local d
  for d in node_modules/.bin .venv/bin; do
    [ -x "$P/$d/$1" ] && { echo "$P/$d/$1"; return 0; }
  done
  command -v "$1"
}

# settings_hooks: a "__disable__ <true|false>" line, then one "<event> <command> <first-arg>" line per registered hook; command is ARRAY when not a string.
settings_hooks() {
  if have python3; then
    python3 - "${1:-$P/.claude/settings.json}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("__disable__", str(d.get("disableAllHooks", False)).lower(), "")
for ev, groups in d.get("hooks", {}).items():
    for g in groups:
        for h in g.get("hooks", []):
            c = h.get("command"); a = h.get("args") or [""]
            print(ev, c if isinstance(c, str) else "ARRAY", a[0])
PY
  elif have node; then
    node - "${1:-$P/.claude/settings.json}" <<'JS'
const d = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
console.log("__disable__", String(d.disableAllHooks === true), "");
for (const [ev, groups] of Object.entries(d.hooks || {}))
  for (const g of groups) for (const h of g.hooks || []) {
    const a = h.args && h.args.length ? h.args[0] : "";
    console.log(ev, typeof h.command === "string" ? h.command : "ARRAY", a);
  }
JS
  else return 3; fi
}

# section_lines <file> <key>: the non-comment lines of one top-level section of a YAML file.
section_lines() { awk -v k="$2" '/^[^[:space:]#]/ { on = ($0 ~ "^" k ":") } on && !/^[[:space:]]*#/' "$1"; }

# gitleaks_state <file>: ok, mixed, multi, key:<name>, arg:<text>, form, dup, duphook, overlay, skip or none for the pre-commit section. A command counts as ok only when all of these hold.
# The run value (a plain scalar continues on every following blank or deeper-indented line, joined with one space, as YAML folds it; a trailing lone backslash is refused) has a trailing shell comment removed per line and is exactly one simple command, or the single non-blank, non-comment line of a run: | block, or the seeded guard `if command -v gitleaks ...; then <command>; fi`.
# The command is the bare gitleaks binary, npx/pnpx/bunx gitleaks, pnpm/yarn/npm/bun exec|dlx gitleaks (not run, which starts a package script, and not a path before gitleaks), or docker run (--rm, -i, -t, -v/--volume, -w/--workdir) <image>; no env prefix.
# Its subcommand is git, protect, detect or dir, and its arguments are only --pre-commit, --staged, --redact [N], -v, --verbose, --no-banner, --no-color, --log-level <v>, -c/--config <one relative path of [A-Za-z0-9._/-] with no .. or empty segment, to an existing non-empty regular file inside the project>, and in the docker form a positional path.
# The command has one run: key and only the keys run, name, tags, stage_fixed, fail_text, priority, root and skip: false; pre-commit has only commands, jobs, scripts, parallel, piped, follow, fail_on_changes and skip: false; any other key is key:<name>, and top-level exclude_tags is refused. A line that is not a plain bare key: value (quoted or explicit key, space before the colon, merge key, alias, anchor, flow mapping) is form. A repeated command name under commands: is dup (jobs: compare the name: value), a repeated pre-commit: or a repeated key directly under it is duphook, a backslash in the run value is form, and lefthook-local.yml or top-level extends:/remotes: gives overlay, never ok. A trailing CR is stripped, so CRLF reads as LF. mixed: gitleaks appears next to an unquoted | & ; ( ) backtick, $( or another line, or a line ends in a backslash. multi: a command with gitleaks has more than one run: key.
gitleaks_state() {
  local r out d root pd p plain=0 valid=0 firstbad=""
  out=$(awk '
    BEGIN {
      guard = "^if[ \t]+command[ \t]+-v[ \t]+gitleaks[^;|()`]*;[ \t]*then[ \t]+[^;&|()`]*;[ \t]*fi$"
      run = "((npx|pnpx|bunx)[ \t]+(-[-A-Za-z]+[ \t]+)*|(pnpm|yarn|npm|bun)[ \t]+(exec|dlx)[ \t]+(--[ \t]+)?)?"
      sub_ = "[ \t]+(git|detect|protect|dir|stdin)([ \t]|$)"
      loose = "(^|[;&|(]|then|do|else)[ \t]*([A-Za-z_][A-Za-z0-9_]*=[^ \t]+[ \t]+)*"
      looseany = loose run "([^ \t]*/)?gitleaks" sub_ "|" loose "docker[ \t]+run[ \t]+.*gitleaks[^ \t]*" sub_
    }
    function indent(l) { match(l, /[^ \t]/); return RSTART - 1 }
    function lone(l) { sub(/[ \t]+$/, "", l); return l ~ /(^|[^\\])(\\\\)*\\$/ }
    function uncomment(v,   i, c, q, o, n) {
      q = ""; o = ""; n = length(v)
      for (i = 1; i <= n; i++) {
        c = substr(v, i, 1)
        if (c == "\\" && q != "\047") { o = o c substr(v, i + 1, 1); i++; continue }
        if (q == "") { if (c == "#" && (i == 1 || substr(v, i - 1, 1) ~ /[ \t]/)) break; if (c == "\047" || c == "\"") q = c }
        else if (c == q) q = ""
        o = o c
      }
      sub(/^[ \t]+/, "", o); sub(/[ \t]+$/, "", o)
      return o
    }
    function strip(v,   i, c, q, o, n, f) {
      ops = 0; q = ""; o = ""; n = length(v); f = substr(v, 1, 1)
      if ((f == "\"" || f == "\047") && n > 1 && substr(v, n, 1) == f) { v = substr(v, 2, n - 2); n -= 2 }
      for (i = 1; i <= n; i++) {
        c = substr(v, i, 1)
        if (c == "\\" && q != "\047") { o = o c substr(v, i + 1, 1); i++; continue }
        if (q == "") {
          if (c == "#" && (i == 1 || substr(v, i - 1, 1) ~ /[ \t]/)) break
          if (c == "\047" || c == "\"") q = c
          else if (c ~ /[|&;()`]/) ops = 1
          else if (c == "$" && substr(v, i + 1, 1) == "(") ops = 1
        } else if (c == q) q = ""
        o = o c
      }
      sub(/^[ \t]+/, "", o); sub(/[ \t]+$/, "", o)
      return o
    }
    function tok(s,   i, n, c, q, w, inw) {
      NW = 0; w = ""; inw = 0; q = ""; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q == "") {
          if (c ~ /[ \t]/) { if (inw) { W[++NW] = w; w = ""; inw = 0 } continue }
          if (c == "\\") { i++; w = w substr(s, i, 1); inw = 1; continue }
          if (c == "\047" || c == "\"") { q = c; inw = 1; continue }
          w = w c; inw = 1
        } else if (c == q) q = ""
        else if (c == "\\" && q == "\"") { i++; w = w substr(s, i, 1) }
        else w = w c
      }
      if (inw) W[++NW] = w
    }
    function badcfg(v,   k, n, sg) {
      if (v == "" || v !~ /^[A-Za-z0-9._\/-]+$/ || v ~ /^[\/-]/ || v ~ /\/$/) return 1
      n = split(v, sg, "/")
      for (k = 1; k <= n; k++) if (sg[k] == ".." || sg[k] == "") return 1
      if (CFGV != "") return 1
      CFGV = v
      return 0 }
    function gl(w) { return w ~ /(^|\/)gitleaks(:[^\/]*)?$/ }
    function classify(s,   i, envw, dock, f, badf, a, v) {
      tok(s); i = 1; envw = ""; dock = 0; badf = ""; CFGV = ""
      while (i <= NW && W[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { if (envw == "") { envw = W[i]; sub(/=.*$/, "", envw) } i++ }
      if (W[i] ~ /^(npx|pnpx|bunx)$/) { i++; while (i <= NW && W[i] ~ /^-[-A-Za-z]+$/) i++ }
      else if (W[i] ~ /^(pnpm|yarn|npm|bun)$/ && W[i + 1] ~ /^(exec|dlx)$/) { i += 2; if (W[i] == "--") i++ }
      else if (W[i] ~ /^(pnpm|yarn|npm|bun)$/ && W[i + 1] == "run") {
        for (f = i + 2; f <= NW; f++) if (W[f] ~ /gitleaks/) return "arg:" W[i] " run"
        return "" }
      else if (W[i] == "docker" && W[i + 1] == "run") {
        i += 2; dock = 1
        while (i <= NW && W[i] ~ /^-/) {
          f = W[i]
          if (f ~ /^(--rm|-i|-t|-it|-ti)$/) i++
          else if (f ~ /^(-v|--volume|-w|--workdir)$/) i += 2
          else if (f ~ /^(--volume|--workdir)=/) i++
          else { if (badf == "") badf = f; if (W[i + 1] !~ /^-/ && !gl(W[i + 1])) i += 2; else i++ }
        }
        if (i <= NW && !gl(W[i])) i++
      }
      if (dock) { if (!gl(W[i])) return "" }
      else if (W[i] != "gitleaks") { if (W[i] ~ /gitleaks/) return "arg:" W[i]; return "" }
      i++
      if (W[i] !~ /^(git|protect|detect|dir)$/) return ""
      i++
      if (envw != "") return "arg:" envw "= (an env prefix)"
      if (badf != "") return "arg:" badf
      while (i <= NW) {
        a = W[i]
        if (a ~ /^(--pre-commit|--staged|-v|--verbose|--no-banner|--no-color)$/) { i++; continue }
        if (a == "--redact") { i++; if (W[i] ~ /^[0-9]+$/) i++; continue }
        if (a ~ /^--redact=[0-9]*$/) { i++; continue }
        if (a == "--log-level") { if (i + 1 > NW) return "arg:" a; i += 2; continue }
        if (a ~ /^--log-level=/) { i++; continue }
        if (a == "-c" || a == "--config") { v = W[i + 1]; if (i + 1 > NW || badcfg(v)) return "arg:" a " " v; i += 2; continue }
        if (a ~ /^--config=/) { v = substr(a, 10); if (badcfg(v)) return "arg:" a; i++; continue }
        if (dock && a !~ /^-/) { i++; continue }
        return "arg:" a
      }
      return "ok"
    }
    function ev(v,   s) {
      s = strip(v)
      if (s ~ guard) { sub(/^if[ \t]+command[ \t]+-v[ \t]+gitleaks[^;|()`]*;[ \t]*then[ \t]+/, "", s); sub(/;[ \t]*fi$/, "", s); s = strip(s) }
      if (s !~ /gitleaks/) return ""
      if (ops) return (s ~ looseany) ? "mixed" : ""
      return classify(s)
    }
    function plain_add(l) { if (lone(l)) bs = 1; l = uncomment(l); if (l == "") return; if (l ~ /\\/) hasbs = 1; pv = (pv == "" ? l : pv " " l) }
    function block_add(l) { if (l ~ /^[ \t]*#/ || l !~ /[^ \t]/) return; if (lone(l)) bs = 1; if (uncomment(l) ~ /\\/) hasbs = 1; bl[++nb] = l }
    function run_start(v) {
      nrun++; inrun = 1; bs = 0; hasbs = 0; nb = 0; pv = ""
      if (v ~ /^[|>][-+]?[ \t]*$/) { mode = "block"; return }
      mode = "plain"; plain_add(v)
    }
    function run_end(   i, st) {
      if (!inrun) return
      inrun = 0; st = ""
      if (mode == "plain") { if (pv ~ /gitleaks/) { anygl = 1; CFGV = ""; st = bs ? "mixed" : hasbs ? "form" : ev(pv); if (st == "ok") curcfg = CFGV } }
      else if (nb == 1) { if (bl[1] ~ /gitleaks/) { anygl = 1; CFGV = ""; st = bs ? "mixed" : hasbs ? "form" : ev(bl[1]); if (st == "ok") curcfg = CFGV } }
      else for (i = 1; i <= nb; i++) if (bl[i] ~ /gitleaks/) { anygl = 1; st = "mixed" }
      if (st != "" && res == "") res = st
    }
    function note(r) { if (bad == "") bad = r }
    function gnote(r) { if (gbad == "") gbad = r }
    function endcmd() {
      run_end()
      if (cmd != "") {
        nm[cmdname]++
        if (anygl) glc[cmdname] = 1
        if (nrun > 1 && anygl) note("multi")
        else if (res == "ok") { if (cmdform) note("form"); else if (kbad == "skip") skipped = 1; else if (kbad != "") note(kbad); else { okn++; if (curcfg == "") okplain++; else cfgs[++ncfg] = curcfg } }
        else if (res != "") note(res)
      }
      cmd = ""; cmdname = ""; nrun = 0; anygl = 0; res = ""; kbad = ""; cmdform = 0; curcfg = ""
    }
    function field(l,   key, val) {
      if (cmd == "") return
      if (l !~ /^      [A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/) { cmdform = 1; return }
      key = l; sub(/^      /, "", key); sub(/:.*$/, "", key)
      val = l; sub(/^      [^:]*:/, "", val); val = uncomment(val)
      if (val ~ /^[*&!]/) cmdform = 1
      if (key == "run") run_start(val)
      else if (key == "skip") { if (val != "false" && kbad == "") kbad = (val == "true") ? "skip" : "key:skip" }
      else if (key ~ /^(name|tags|stage_fixed|fail_text|priority|root)$/) { if (key == "name" && hk == "jobs") cmdname = val }
      else if (kbad == "") kbad = "key:" key
    }
    { sub(/\r$/, "") }
    /^[ \t]*#/ { next }
    /^[^ \t]/ {
      run_end(); endcmd(); on = 0; hk = ""
      if ($0 ~ /^pre-commit[ \t]*:/) { npc++; on = 1; v = $0; sub(/^[^:]*:/, "", v); if (uncomment(v) != "") gnote("form") }
      else if ($0 ~ /^(extends|remotes)[ \t]*:/) overlay = 1
      else if ($0 ~ /^exclude_tags[ \t]*:/) gnote("key:exclude_tags")
      next }
    !on { next }
    inrun && ($0 !~ /[^ \t]/ || indent($0) > 6) { if (mode == "plain") plain_add($0); else block_add($0); next }
    { run_end() }
    $0 !~ /[^ \t]/ { next }
    { ind = indent($0) }
    ind == 2 {
      endcmd(); hk = ""
      if ($0 !~ /^  [A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/) { gnote("form"); next }
      key = $0; sub(/^  /, "", key); sub(/:.*$/, "", key)
      if (hkn[key]++ > 0) gnote("duphook")
      val = $0; sub(/^  [^:]*:/, "", val); val = uncomment(val)
      if (val ~ /^[*&!]/) { gnote("form"); next }
      if (key == "skip") { if (val == "true") hookskip = 1; else if (val != "false") gnote("key:skip") }
      else if (key ~ /^(commands|jobs)$/) { if (val != "") gnote("form"); hk = key }
      else if (key !~ /^(scripts|parallel|piped|follow|fail_on_changes)$/) gnote("key:" key)
      next }
    hk !~ /^(commands|jobs)$/ { next }
    ind == 4 {
      h = $0; sub(/[ \t]+#.*$/, "", h)
      if (hk == "jobs" && h ~ /^    -([ \t]|$)/) { endcmd(); cmd = "job" NR; cmdname = ""; l = $0; sub(/^    -[ \t]*/, "      ", l); field(l) }
      else if (hk == "commands" && h ~ /^    [A-Za-z0-9_-]+:[ \t]*$/) { endcmd(); cmd = h; sub(/^[ \t]+/, "", cmd); sub(/:[ \t]*$/, "", cmd); cmdname = cmd; if (cmdhdr[cmd]++ > 0) gnote("dup") }
      else { endcmd(); gnote("form") }
      next }
    ind == 6 { field($0); next }
    { if (cmd != "") cmdform = 1 }
    END {
      endcmd()
      if (npc > 1) gnote("duphook")
      for (n in glc) if (n != "" && nm[n] > 1) gnote("dup")
      if (gbad != "") r = gbad
      else if (okn > 0 && !hookskip) r = overlay ? "overlay" : "ok"
      else if (bad != "") r = bad
      else if (skipped || okn > 0 || hookskip) r = "skip"
      else r = "none"
      print r
      if (r == "ok" || r == "overlay") { if (okplain > 0) print "P"; for (n = 1; n <= ncfg; n++) print "C " cfgs[n] } }' "$1")
  r=${out%%$'\n'*}
  if [ "$r" = ok ] || [ "$r" = overlay ]; then
    d=$(dirname "$1"); root=$(cd "$d" && pwd -P)
    while IFS= read -r p; do
      case "$p" in
        P) plain=1 ;;
        "C "*) p=${p#C }
          pd=$(cd "$d/$(dirname "$p")" 2>/dev/null && pwd -P)
          if [ -f "$d/$p" ] && [ -s "$d/$p" ] && [ ! -L "$d/$p" ] && [ -n "$pd" ] && case "$pd/" in "$root"/*) true ;; *) false ;; esac; then valid=1
          elif [ -z "$firstbad" ]; then firstbad=$p; fi ;;
      esac
    done <<EOF
${out#*$'\n'}
EOF
    if [ "$plain" = 0 ] && [ "$valid" = 0 ] && [ -n "$firstbad" ]; then r="arg:--config $firstbad"; fi
  fi
  if [ "$r" = ok ] && { [ -f "$(dirname "$1")/lefthook-local.yml" ] || [ -f "$(dirname "$1")/.lefthook-local.yml" ]; }; then r=overlay; fi
  printf '%s\n' "$r"
}

# hook_runs_lefthook <file>: proves the hook file calls lefthook at top level or through the generated call_lefthook function with no top-level exit before it; it does not prove a deliberately obfuscated hook is live.
hook_runs_lefthook() {
  sed -E 's/[[:space:]]#.*$//' "$1" | awk '
    /^[ \t]*(#|echo|printf|:)/ { next }
    {
      l = $0; tmp = l; o = gsub(/(^|[^A-Za-z0-9_])(if|case|while|for|until)[ \t]/, "&", tmp)
      tmp = l; cl = gsub(/(^|[^A-Za-z0-9_])(fi|esac|done)([^A-Za-z0-9_]|$)/, "&", tmp)
      if (l ~ /^[ \t]*\{[ \t]*$/ || l ~ /\)[ \t]*\{[ \t]*$/) o++
      if (l ~ /^[ \t]*\}[ \t]*$/) cl++
      if (d == 0 && l ~ /^[ \t]*exit([ \t]+[0-9]+)?[ \t]*(;.*)?$/) exited = 1
      if (!exited && l ~ /(lefthook|LEFTHOOK_BIN"?|call_lefthook)[ \t]+(run|hook)/) ok = 1
      d += o - cl
    }
    END { exit !ok }'
}

# 1. lefthook binary, config and wired git hooks
lh=$(resolve lefthook)
if [ -n "$lh" ]; then pass "lefthook binary ($lh)"; else fail "lefthook binary" "not in node_modules/.bin, .venv/bin or PATH"; fi
if [ -f "$P/lefthook.yml" ]; then
  for h in pre-commit pre-push; do
    if { section_lines "$P/lefthook.yml" "$h" | grep -Eq '^[[:space:]]+commands:' && section_lines "$P/lefthook.yml" "$h" | grep -Eq '^[[:space:]]{4}[A-Za-z0-9_-]+:'; } \
      || { section_lines "$P/lefthook.yml" "$h" | grep -Eq '^[[:space:]]+jobs:' && section_lines "$P/lefthook.yml" "$h" | grep -Eq '^[[:space:]]{4}-[[:space:]]'; }; then pass "lefthook.yml $h defines commands"
    else fail "lefthook.yml $h" "no $h section with a non-empty commands or jobs block"; fi
  done
  gls=$(gitleaks_state "$P/lefthook.yml")
  case "$gls" in
    ok) pass "lefthook.yml pre-commit runs gitleaks" ;;
    mixed) fail "lefthook.yml gitleaks" "the gitleaks command must be the only command in the run line; a trailing || true, a pipe, a second command, a background marker or a trailing backslash keeps it from blocking; in the docker form use \"\$PWD\" and not \$(pwd)" ;;
    multi) fail "lefthook.yml gitleaks" "the command that runs gitleaks has more than one run: key; keep exactly one" ;;
    key:*) fail "lefthook.yml gitleaks" "${gls#key:}: is not an accepted key here and can switch the scan off or narrow it; the check accepts only commands, jobs, scripts, parallel, piped, follow, fail_on_changes and skip: false in pre-commit, and run, name, tags, stage_fixed, fail_text, priority, root and skip: false on the gitleaks command; exclude_tags is refused at the top level" ;;
    arg:*) fail "lefthook.yml gitleaks" "argument ${gls#arg:} is not accepted; the scan may use only git, protect, detect or dir with --pre-commit, --staged, --redact, -v, --verbose, --no-banner, --no-color, --log-level and a --config value that is a relative path of letters, digits, dot, dash, underscore and slash, with no .. segment, to an existing non-empty regular file inside the project; npm, pnpm, yarn or bun run and a path to gitleaks are not accepted, use the bare gitleaks binary, npx, pnpx, bunx or pnpm, yarn, npm or bun exec or dlx; a positional path is accepted only in the docker form" ;;
    form) fail "lefthook.yml gitleaks" "lefthook.yml uses a YAML form the check cannot read (a quoted or explicit key, a space before the colon, a merge key, an alias or anchor, a flow mapping, or a list under a command key); write the gitleaks command plainly" ;;
    dup) fail "lefthook.yml gitleaks" "a command name under commands: is repeated; the later entry can replace the gitleaks one" ;;
    duphook) fail "lefthook.yml gitleaks" "pre-commit: or a key under it appears more than once; the later one can replace the earlier; keep one" ;;
    overlay) fail "lefthook.yml gitleaks" "lefthook-local.yml, extends: or remotes: can change the pre-commit hook; check it by hand or remove it" ;;
    skip) fail "lefthook.yml gitleaks" "the gitleaks command or the pre-commit hook sets skip: true" ;;
    *) fail "lefthook.yml gitleaks" "no run line in pre-commit invokes gitleaks (git, detect, protect or dir) outside a comment; the check reads only two-space indentation (commands: at 2 spaces, command names at 4, fields at 6), not 4-space indentation or flow mappings, and a bare gitleaks dir . is not accepted" ;;
  esac
  if git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    hooks_dir=$(git -C "$P" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)
    for h in pre-commit commit-msg pre-push; do
      grep -Eq "^$h:" "$P/lefthook.yml" || continue
      if [ -f "$hooks_dir/$h" ] && [ -x "$hooks_dir/$h" ] && hook_runs_lefthook "$hooks_dir/$h"; then pass "git hook $h executable and calls lefthook"
      else fail "git hook $h" "lefthook.yml defines it but $hooks_dir/$h is missing, not executable, or does not run lefthook before any top-level exit; run lefthook install"; fi
    done
  else fail "git hooks" "not a git repository"; fi
else fail "lefthook.yml" "missing"; fi

# 2. gitleaks and its config
gl=$(resolve gitleaks)
if [ -n "$gl" ]; then pass "gitleaks binary ($gl)"; else fail "gitleaks binary" "not resolvable; install it"; fi
if [ -f "$P/.gitleaks.toml" ]; then pass ".gitleaks.toml present"; else fail ".gitleaks.toml" "missing"; fi

# 3. agent hooks: seeded, executable when run as scripts, registered under the right event in settings.json in exec form
# fire <hook-file> <payload>: run a guard in the project on a synthetic payload; prints "<exit status> <stderr>". The guards only read.
fire() {
  local out rc
  case "$1" in
    *.sh) out=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$1" 2>&1 >/dev/null <<<"$2"); rc=$? ;;
    *.py) out=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$1" 2>&1 >/dev/null <<<"$2"); rc=$? ;;
    *) out=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" node "$1" 2>&1 >/dev/null <<<"$2"); rc=$? ;;
  esac
  echo "$rc $out"
}
if [ -f "$P/.claude/settings.json" ]; then
  reg=$(settings_hooks) || reg=FAILED
  if [ "$reg" = FAILED ]; then fail ".claude/settings.json" "unreadable, or neither python3 nor node is available"; reg=; fi
  if printf '%s\n' "$reg" | grep -q '^__disable__ true'; then fail "settings.json disableAllHooks" "true turns every hook off"; fi
  if printf '%s\n' "$reg" | grep -q ' ARRAY '; then fail "settings.json hooks" "an array-valued command never runs; use exec form (command + args)"; fi
  for pair in protect-files:PreToolUse block-no-verify:PreToolUse user-prompt-guard:UserPromptSubmit post-edit-typecheck:PostToolUse post-edit-comment-check:PostToolUse stop-checks:Stop subagent-stop:SubagentStop session-context:SessionStart skill-usage-log:PostToolUse; do
    name=${pair%%:*}; event=${pair#*:}
    file=$(find "$P/.claude/hooks" -maxdepth 1 -name "$name.*" 2>/dev/null | head -1)
    if [ -z "$file" ]; then fail "hook $name" "script missing under .claude/hooks"; continue; fi
    case "$file" in
      *.sh) [ -x "$file" ] || { fail "hook $name" "$(basename "$file") is not executable"; continue; } ;;
    esac
    want="/.claude/hooks/$(basename "$file")"
    if printf '%s\n' "$reg" | awk -v w="$want" -v e="$event" '$1 == e { n = length($NF) - length(w) + 1; if (n > 0 && substr($NF, n) == w) f = 1 } END { exit !f }'; then pass "hook $name executable and registered under $event"
    else fail "hook $name" "not registered under $event in .claude/settings.json"; fi
  done
else fail ".claude/settings.json" "missing"; fi
if [ -f "$P/.claude/settings.local.json" ]; then
  if ! loc=$(settings_hooks "$P/.claude/settings.local.json" 2>/dev/null); then fail "settings.local.json" "unreadable or not valid JSON"
  elif printf '%s\n' "$loc" | grep -q '^__disable__ true'; then fail "settings.local.json disableAllHooks" "true turns every hook off"
  else pass "settings.local.json does not disable hooks"; fi
fi

# 3b. fire the two blocking guards on a synthetic payload; a no-op script passes the checks above but not this
guard_file() { find "$P/.claude/hooks" -maxdepth 1 -name "$1.*" 2>/dev/null | head -1; }
gf=$(guard_file protect-files)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Write","tool_input":{"file_path":".env","content":"x"}}') # PAYLOAD: synthetic, never read
  if [ "${r%% *}" = 2 ] && [[ "$r" == *BLOCKED* ]]; then pass "protect-files blocks a write to an environment file"; else fail "protect-files guard" "a synthetic secret write was not blocked (exit ${r%% *})"; fi
fi
gf=$(guard_file block-no-verify)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}')
  if [ "${r%% *}" = 2 ] && [[ "$r" == *BLOCKED* ]]; then pass "block-no-verify blocks git commit --no-verify"; else fail "block-no-verify guard" "a synthetic --no-verify commit was not blocked (exit ${r%% *})"; fi
fi

# 3b2. each guard also lets a benign payload through, so a hook that always blocks does not pass
gf=$(guard_file protect-files)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Write","tool_input":{"file_path":"src/x.txt","content":"x"}}')
  if [ "${r%% *}" = 0 ]; then pass "protect-files allows an ordinary write"; else fail "protect-files guard" "an ordinary write was blocked (exit ${r%% *})"; fi
fi
gf=$(guard_file block-no-verify)
if [ -n "$gf" ]; then
  r=$(fire "$gf" '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
  if [ "${r%% *}" = 0 ]; then pass "block-no-verify allows git status"; else fail "block-no-verify guard" "git status was blocked (exit ${r%% *})"; fi
fi
echo "NOTE: the other hooks are not fired; their content is covered by the .claude/verify-harness.sh hash check below."

# 3c. integrity: seeded guard files still hash to their origin, which also catches a hook replaced by a no-op
if [ -f "$P/.claude/verify-harness.sh" ]; then
  if vout=$(cd "$P" && bash .claude/verify-harness.sh 2>&1); then pass "verify-harness.sh: enforcement files match their origin hashes"
  else fail "verify-harness.sh" "$(printf '%s' "$vout" | tr '\n' ' ' | cut -c1-200)"; fi
else fail ".claude/verify-harness.sh" "missing"; fi

# 4. CI workflow runs the gates
ci=()
for f in "$P"/.github/workflows/*.yml "$P"/.github/workflows/*.yaml "$P"/azure-pipelines.yml "$P"/azure-pipelines/*.yml; do
  [ -f "$f" ] && ci+=("$f")
done
if [ "${#ci[@]}" -eq 0 ]; then fail "CI workflow" "no .github/workflows or azure-pipelines file"
else
  if grep -hv '^[[:space:]]*#' "${ci[@]}" | grep -q 'ci-gates.sh'; then pass "CI runs .claude/ci-gates.sh"; else fail "CI gates" "no workflow line outside a comment runs .claude/ci-gates.sh"; fi
  if grep -hv '^[[:space:]]*#' "${ci[@]}" | grep -q 'verify-harness.sh'; then pass "CI runs .claude/verify-harness.sh"; else fail "CI harness check" "no workflow line outside a comment runs .claude/verify-harness.sh"; fi
fi
[ -f "$P/.claude/ci-gates.sh" ] || fail ".claude/ci-gates.sh" "missing"

if [ "$FAILS" -gt 0 ]; then echo "FAIL: $FAILS item(s) not live."; exit 1; fi
echo "OK: harness is live."

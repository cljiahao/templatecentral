#!/usr/bin/env bash
# scripts/defect-report.test.sh — tests for skills/migrate/general/defect-report.sh and its checks in defects/*.sh.
# Each check flags its "old" fixture, stays quiet on the current template file copied from the real template tree,
# counts an absent file as "not installed", ignores dependency folders, never writes into the project and exits as documented.
# Usage: bash scripts/defect-report.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/skills/migrate/general/defect-report.sh"
DEFECTS="$REPO_ROOT/skills/migrate/general/defects"
FIXTURES="$REPO_ROOT/tests/fixtures/defects"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
lacks() { # lacks <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] found in [$2]"; else PASS=$((PASS + 1)); fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/dr.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# truth <command...>: print 1 when the command succeeds, 0 when it fails.
truth() {
  if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi
}

# run <dir> [args]: sets OUT and EC from running the report with the CI markers cleared.
run() {
  local d=$1
  shift
  OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$RUNNER" "$d" "$@" 2>&1)
  EC=$?
}

# sig <dir>: a hash of the file list and every file's content, so any write shows as a difference.
sig() {
  (
    cd "$1" || exit 1
    find . | LC_ALL=C sort
    find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$f"; else sha256sum -- "$f"; fi
    done
  ) | if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi
}

# meta <file> <variable>: print one variable from a check file, read in a subshell.
meta() {
  (
    id='' level='' template=''
    # shellcheck source=/dev/null
    . "$1"
    case "$2" in id) echo "$id" ;; level) echo "$level" ;; template) echo "$template" ;; esac
  )
}

NCHECKS=0
for def in "$DEFECTS"/*.sh; do NCHECKS=$((NCHECKS + 1)); done
SUMMARY_TAIL="This is a list of known older template patterns, not an audit."

# ── every check: old fixture is flagged, current template is clean ───────────

for def in "$DEFECTS"/*.sh; do
  id=$(meta "$def" id)
  level=$(meta "$def" level)
  template=$(meta "$def" template)
  old="$FIXTURES/$id/old"
  check 1 "$(truth test -d "$old")" "fixture exists for $id"
  [[ -d "$old" ]] || continue

  run "$old"
  want=0
  if [[ "$level" == high ]]; then want=1; fi
  check "$want" "$EC" "$id: exit code for level $level"
  has "  $id  $level  matches an older template pattern: " "$OUT" "$id: flagged with its id and level"
  has "Current template: $template" "$OUT" "$id: names the current template"
  has "Fix: " "$OUT" "$id: carries a fix"

  # The control: the same layout with the current template file in place of each old file.
  clean="$T/clean-$id"
  rm -rf "$clean"
  mkdir -p "$clean"
  cp -R "$old/." "$clean/"
  while IFS= read -r f; do
    base=$(basename "$f")
    src=
    if [[ "$base" == "$(basename "$template")" && -f "$REPO_ROOT/$template" ]]; then src="$REPO_ROOT/$template"; fi
    if [[ "$base" == redact_sensitive_output.py ]]; then src="$REPO_ROOT/skills/add/redaction/hook-python/template/.claude/hooks/redact_sensitive_output.py"; fi
    if [[ -n "$src" ]]; then
      [[ -f "$src" ]] || { FAIL=$((FAIL + 1)); echo "FAIL: $id: template file missing: $src"; continue; }
      cp "$src" "$clean/$f"
    fi
  done < <(cd "$old" && find . -type f | sed 's|^\./||')
  if [[ "$id" == argon2-dummy-hash-literal ]]; then
    # The current template is a fence in a leaf, so the control is: no template text carries the literal, and the old fixture files are removed.
    rm -rf "$clean"
    mkdir -p "$clean"
    lit=$(grep -rlF 'c29tZXNhbHRzb21lc2E' "$REPO_ROOT/skills" | grep -v '/defects/\|UPGRADE-NOTES' || true)
    check "" "$lit" "$id: no current template contains the older literal"
    printf 'const DUMMY_HASH = argon2.hash(randomUUID());\n' > "$clean/auth.service.ts"
  fi
  if [[ "$id" == exclusion-audit ]]; then
    # The template is a gate script, not a config, so the control is a project with the same config file and no exclude (the audit prints a line for every exclude, even one with a reason).
    printf 'sonar.projectKey=demo\n' > "$clean/sonar-project.properties"
  fi
  run "$clean"
  check 0 "$EC" "$id: current template is clean (exit)"
  lacks "  $id  " "$OUT" "$id: current template is not flagged"
done

# ── runner behaviour ─────────────────────────────────────────────────────────

# An absent file is "not installed", not clean.
mkdir -p "$T/empty"
run "$T/empty"
check 0 "$EC" "empty project exits 0"
check "$NCHECKS checks run, 0 matched, $NCHECKS not installed. $SUMMARY_TAIL" "$OUT" "empty project: every check counts as not installed"

# One installed target: the others stay "not installed".
run "$FIXTURES/mongoose-client-promise-retry/old"
has "$NCHECKS checks run, 2 matched, $((NCHECKS - 2)) not installed. $SUMMARY_TAIL" "$OUT" "summary line: checks, matches, not installed"

# A match inside a dependency folder is ignored.
for skip in node_modules .venv venv .next dist build coverage .git __pycache__; do
  d="$T/skip-$skip/$skip/pkg"
  mkdir -p "$d"
  cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$d/"
  run "$T/skip-$skip"
  check 0 "$EC" "a match inside $skip is ignored (exit)"
  check "$NCHECKS checks run, 0 matched, $NCHECKS not installed. $SUMMARY_TAIL" "$OUT" "a match inside $skip counts as not installed"
done

# A skipped candidate (over 1 MB, symlink, newline in the path) is never scanned and never counted as not installed.
mkdir -p "$T/big/src/integrations/database"
cp "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/big/src/integrations/database/"
head -c 1100000 /dev/zero | tr '\0' ' ' >> "$T/big/src/integrations/database/mongoose-client.ts"
run "$T/big"
check 2 "$EC" "a file over 1 MB as the only candidate exits 2"
has "every candidate file was skipped" "$OUT" "over 1 MB: the run says nothing was scanned"
mkdir -p "$T/link/src"
ln -s "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/link/src/mongoose-client.ts"
run "$T/link"
check 2 "$EC" "a symlink as the only candidate exits 2"
has "every candidate file was skipped" "$OUT" "symlink: the run says nothing was scanned"
mkdir -p "$T/nl/a
b"
cp "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/nl/a
b/"
run "$T/nl"
check 2 "$EC" "a newline in the path as the only candidate exits 2"

# One scanned file plus skipped ones: the scan runs, one stderr line gives the number skipped.
mkdir -p "$T/mix/src" "$T/mix/other"
cp "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/mix/src/"
ln -s "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/mix/other/mongoose-client.ts"
head -c 1100000 /dev/zero | tr '\0' ' ' > "$T/mix/other/big-pad"
cp "$T/mix/src/mongoose-client.ts" "$T/mix/other/pad.ts"
head -c 1100000 /dev/zero | tr '\0' ' ' >> "$T/mix/other/pad.ts"
mkdir -p "$T/mix/deep"
cp "$T/mix/other/pad.ts" "$T/mix/deep/mongoose-client.ts"
run "$T/mix"
check 1 "$EC" "skipped files beside a scanned one: the scanned one is still flagged"
has "2 candidate file(s) were not scanned" "$OUT" "skipped count is printed once on stderr"

# A project folder named like a pruned folder is still scanned.
for root in build dist coverage venv node_modules; do
  mkdir -p "$T/rootname/$root"
  cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$T/rootname/$root/"
  run "$T/rootname/$root"
  check 1 "$EC" "a project directory named $root is scanned (exit)"
  has "mongoose-client-promise-retry  high" "$OUT" "a project directory named $root is scanned (match)"
done

# An unreadable target file exits 2 and names the file.
mkdir -p "$T/unread"
cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$T/unread/"
chmod 000 "$T/unread/src/integrations/database/mongoose-client.ts"
if [[ ! -r "$T/unread/src/integrations/database/mongoose-client.ts" ]]; then
  run "$T/unread"
  check 2 "$EC" "an unreadable target file exits 2"
  has "src/integrations/database/mongoose-client.ts (check mongoose-client-promise-retry)" "$OUT" "the unreadable file is named"
fi
chmod 644 "$T/unread/src/integrations/database/mongoose-client.ts"

# A check that fails, exits non-zero at load, or exits at the top level fails closed.
cp -R "$REPO_ROOT/skills/migrate/general" "$T/gen2"
printf 'id=zz\nlevel=check\nnames=mongoose-client.ts\ntemplate=t\ndesc=d\nfix=f\ncheck() { false; }\n' > "$T/gen2/defects/zz.sh"
OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$T/gen2/defect-report.sh" "$FIXTURES/mongoose-client-promise-retry/old" 2>&1)
check 2 "$?" "a check that exits non-zero ends the run with exit 2"
has "check zz failed" "$OUT" "the failing check is named by id"
cat > "$T/gen2/defects/zz.sh" <<'EOF'
id=zz
level=check
names=mongoose-client.ts
template=t
desc=d
fix=f
check() { echo "$1:1"; return 3; }
EOF
OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$T/gen2/defect-report.sh" "$FIXTURES/mongoose-client-promise-retry/old" 2>&1)
check 2 "$?" "a check that prints a match and then fails still exits 2"
printf 'id=zz\nlevel=check\nnames=mongoose-client.ts\ntemplate=t\ndesc=d\nfix=f\ncheck() { :; }\nexit 0\n' > "$T/gen2/defects/zz.sh"
OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$T/gen2/defect-report.sh" "$T/empty" 2>&1)
check 2 "$?" "a check file with a top-level exit ends the run with exit 2"
has "exits or fails while loading" "$OUT" "the top-level exit is named"
rm -f "$T/gen2/defects/zz.sh"

# strip_comments variants for the promise-retry check: the old pattern is flagged, the fixed pattern is clean.
# vclient <name> <ident> <await-expr> <catch-body> <extra>: writes a client and runs the report on it.
vclient() {
  local d="$T/v-$1"
  mkdir -p "$d/src"
  printf 'const %s = { conn: null, promise: null };\nexport async function connectDB() {\n  if (!%s.promise) { %s.promise = mongoose.connect(URL); }\n  try {\n    const conn = %s;\n    %s.conn = conn;\n  } catch (error) {\n    %s\n    throw error;\n  }\n}\n%s\n' \
    "$2" "$2" "$2" "$3" "$2" "$4" "$5" > "$d/src/mongoose-client.ts"
  run "$d"
}
flagged() { has "mongoose-client-promise-retry  high" "$OUT" "$1: flagged"; }
unflagged() { lacks "mongoose-client-promise-retry  " "$OUT" "$1: not flagged"; }

vclient old-plain cached 'await cached.promise' '' ''
flagged "old client with no reset"
vclient old-disconnect cached 'await cached.promise' '' 'export async function disconnect() { cached.promise = null; }'
flagged "old client, reset only in a disconnect helper"
vclient old-comment cached 'await cached.promise' '// cached.promise = null' '/* cached.promise = null */'
flagged "old client, reset only inside comments"
vclient old-spaces cached 'await   cached.promise' '' ''
flagged "old client, await with extra spaces"
vclient old-paren cached 'await (cached.promise)' '' ''
flagged "old client, await in parentheses"
vclient old-renamed cache 'await cache.promise' '' ''
flagged "old client, renamed variable"
vclient old-other-ident cached 'await cached.promise' 'other.promise = null;' ''
flagged "old client, a different identifier is reset"
vclient old-eq cached 'await cached.promise' 'cached.promise == null;' ''
flagged "old client, a comparison is not a reset"
vclient fixed-nospace cached 'await cached.promise' 'cached.promise=null;' ''
unflagged "fixed client, reset without spaces"
vclient fixed-undefined cached 'await cached.promise' 'cached.promise = undefined;' ''
unflagged "fixed client, reset to undefined"
vclient fixed-renamed cache 'await cache.promise' 'cache.promise = null;' ''
unflagged "fixed client, renamed variable with its reset"
vclient fixed-catch-call cached 'await cached.promise' '' 'export const f = () => cached.promise.catch(() => { cached.promise = null; });'
unflagged "fixed client, reset in a .catch callback"

# Comments never hide or fake a match for the other checks.
mkdir -p "$T/c1/src" "$T/c2/src" "$T/c3" "$T/c4" "$T/c5" "$T/c6"
printf '// connectDB\nexport const x = 1;\n' > "$T/c1/src/mongoose-client.ts"
run "$T/c1"
lacks "mongoose-init-nextjs  " "$OUT" "a comment naming connectDB does not match"
printf 'export async function connectDB() {\n  // call .init() later\n  return 1;\n}\n' > "$T/c2/src/mongoose-client.ts"
run "$T/c2"
has "mongoose-init-nextjs  check" "$OUT" "a comment naming .init() does not hide the match"
printf 'MongooseModule.forRoot(url);\n/* every model .init() */\n' > "$T/c3/database.module.ts"
run "$T/c3"
has "mongoose-init-nestjs  check" "$OUT" "a block comment naming .init() does not hide the nestjs match"
printf 'from sqlalchemy import create_async_engine\n# sslmode=verify-full\nengine = create_async_engine(url)\n' > "$T/c4/session.py"
run "$T/c4"
has "session.py:3  sqlalchemy-tls-verify  check" "$OUT" "an async engine with sslmode only in a comment is flagged"
printf 'engine = create_async_engine(url, connect_args={"sslmode": "verify-full"})\n' > "$T/c5/session.py"
run "$T/c5"
lacks "sqlalchemy-tls-verify  " "$OUT" "an async engine with sslmode in connect_args is clean"
printf '"""Docstring about sslmode."""\nengine = create_engine(url)\n' > "$T/c6/session.py"
run "$T/c6"
lacks "sqlalchemy-tls-verify  " "$OUT" "a docstring naming sslmode counts as a string (documented limit)"
mkdir -p "$T/c7" "$T/c8"
printf 'URL = """postgresql://h/db?sslmode=require"""\nengine = create_async_engine(URL)\n' > "$T/c7/session.py"
run "$T/c7"
lacks "sqlalchemy-tls-verify  " "$OUT" "a triple-quoted URL carrying sslmode is not flagged"
printf 'engine = create_engine (url)\n' > "$T/c8/session.py"
run "$T/c8"
has "session.py:1  sqlalchemy-tls-verify  check" "$OUT" "a space before the paren of create_engine is still matched"

# A bearer-token auth service is not flagged; a cookie-mode one without the header is.
mkdir -p "$T/b1" "$T/b2" "$T/b3"
cat > "$T/b1/auth-service.ts" <<'EOF'
export async function loginWithCredentials() {}
await fetch(`${base}/logout`, { headers: { Authorization: `Bearer ${t}` } });
EOF
run "$T/b1"
lacks "vite-auth-csrf  " "$OUT" "a bearer-token client is not flagged"
cat > "$T/b2/auth-service.ts" <<'EOF'
export async function loginWithCredentials() { await fetch(u, { credentials: "include" }); }
await fetch(`${base}/logout`, { method: "POST", credentials: "include" });
EOF
run "$T/b2"
has "vite-auth-csrf  high" "$OUT" "a cookie-mode client with no CSRF header is flagged"
cat > "$T/b3/auth-service.ts" <<'EOF'
// X-CSRF-Token
export async function loginWithCredentials() { await fetch(u, { credentials: "include" }); }
await fetch(`${base}/logout`, { credentials: "include" });
EOF
run "$T/b3"
has "vite-auth-csrf  high" "$OUT" "a comment naming X-CSRF-Token does not hide the match"

# More shapes for the promise-retry check. xclient <name> <body> writes a client file and runs the report on it.
xclient() {
  local d="$T/x-$1"
  mkdir -p "$d/src"
  printf '%s\n' "$2" > "$d/src/mongoose-client.ts"
  run "$d"
}
xclient catch-call-then-helper 'x.catch(noop);
export function resetCache() { cached.promise = null; }
export async function connectDB() { cached.conn = await cached.promise; return cached.conn; }'
flagged ".catch(fn) with no brace does not turn a later block into a catch"
xclient other-function-catch 'export async function connectDB() { cached.conn = await cached.promise; return cached.conn; }
export async function disconnectDB() { try { await mongoose.disconnect(); } catch (e) { cached.promise = null; } }'
flagged "a reset in another function's catch does not count"
xclient try-without-catch 'export async function connectDB() { try { cached.conn = await cached.promise; } finally { cached.promise = null; } }'
flagged "a reset only in finally still flags"
xclient destructured-catch 'export async function connectDB() {
  try { cached.conn = await cached.promise; } catch ({ message }) { cached.promise = null; throw new Error(message); }
}'
unflagged "a destructured catch binding with a reset"
xclient optional-catch 'export async function connectDB() { try { cached.conn = await cached.promise; } catch { cached.promise = null; throw new Error("x"); } }'
unflagged "a catch with no binding and a reset"
xclient delete-reset 'export async function connectDB() { try { cached.conn = await cached.promise; } catch (e) { delete cached.promise; throw e; } }'
unflagged "delete cached.promise in the catch"
xclient object-reset 'export async function connectDB() { try { cached.conn = await cached.promise; } catch (e) { cached = { conn: null, promise: null }; throw e; } }'
unflagged "whole-object reassign in the catch"
xclient arrow-reset 'export async function connectDB() { cached.conn = await cached.promise.catch((e) => (cached.promise = null, Promise.reject(e))); }'
unflagged "reset inside a braceless .catch arrow"
xclient nested-try 'export async function connectDB() { try { try { cached.conn = await cached.promise; } finally { log(); } } catch (e) { cached.promise = null; throw e; } }'
unflagged "an await in an inner try with the reset in the outer catch"
xclient crlf 'export async function connectDB() {
  try { cached.conn = await
 cached.promise; } catch (e) { cached.promise =
 null; throw e; }
}'
printf 'export async function connectDB() {\r\n  try { cached.conn = await\r\n cached.promise; } catch (e) { cached.promise =\r\n null; throw e; }\r\n}\r\n' > "$T/x-crlf/src/mongoose-client.ts"
run "$T/x-crlf"
unflagged "CRLF line ends around await and the reset"
printf 'export async function connectDB() {\r\n  cached.conn = await\r\n cached.promise;\r\n}\r\n' > "$T/x-crlf/src/mongoose-client.ts"
run "$T/x-crlf"
flagged "CRLF line ends around an await with no reset"

# A 300 KB client is read in linear time.
mkdir -p "$T/perf/src"
{
  head -n 1 "$T/x-crlf/src/mongoose-client.ts" | tr -d '\r'
  i=0
  while [[ $i -lt 6000 ]]; do printf 'const value%d = { a: 1, b: "text %d", c: [1, 2, 3] }; // note\n' "$i" "$i"; i=$((i + 1)); done
  printf 'export async function connectDB() { cached.conn = await cached.promise; }\n'
} > "$T/perf/src/mongoose-client.ts"
start=$SECONDS
run "$T/perf"
took=$((SECONDS - start))
flagged "a 300 KB client is still flagged"
check 1 "$(truth test "$took" -le 5)" "a 300 KB client finishes within 5 seconds (took ${took}s)"

# Comments and strings for the hook and the Argon2 checks.
mkdir -p "$T/r1" "$T/r2" "$T/r3" "$T/r4" "$T/a1" "$T/a2" "$T/a3"
printf '// TODO read tool_response instead\nconst o = input.tool_output;\n' > "$T/r1/redact-sensitive-output.cjs"
run "$T/r1"
has "redact-sensitive-output.cjs:2  redaction-tool-output  high" "$OUT" "a comment naming tool_response does not hide the older hook"
printf '// was tool_output\nconst o = input.tool_response;\n' > "$T/r2/redact-sensitive-output.cjs"
run "$T/r2"
lacks "redaction-tool-output  " "$OUT" "a fixed hook with tool_output only in a comment is clean"
printf '# TODO read tool_response instead\no = data.get("tool_output")\n' > "$T/r3/redact_sensitive_output.py"
run "$T/r3"
has "redact_sensitive_output.py:2  redaction-tool-output  high" "$OUT" "a Python comment naming tool_response does not hide the older hook"
printf 'o = data.get("tool_response")  # not tool_output\n' > "$T/r4/redact_sensitive_output.py"
run "$T/r4"
lacks "redaction-tool-output  " "$OUT" "a fixed Python hook with tool_output only in a comment is clean"
LIT="\$argon2id\$v=19\$m=65536,t=3,p=1\$c29tZXNhbHRzb21lc2E\$Rdo0OMHkQXBTOTBqNCn0mPvBGiLxvGBIbxKZ0nJ0Aqo"
printf '// const DUMMY = argon2.hash(randomUUID());\nconst DUMMY_HASH = "%s";\n' "$LIT" > "$T/a1/auth.service.ts"
run "$T/a1"
has "auth.service.ts:2  argon2-dummy-hash-literal  check" "$OUT" "a commented-out fix beside the live literal still flags"
printf '// old: "%s"\nconst DUMMY_HASH = argon2.hash(randomUUID());\n' "$LIT" > "$T/a2/auth.service.ts"
run "$T/a2"
lacks "argon2-dummy-hash-literal  " "$OUT" "the literal only in a comment is clean"
printf '# old\nDUMMY_HASH = "%s"\n' "$LIT" > "$T/a3/auth_service.py"
run "$T/a3"
has "auth_service.py:2  argon2-dummy-hash-literal  check" "$OUT" "the literal in Python code flags"

# A symlinked directory pointing outside the project is reported, never read, and never counted as "not installed".
mkdir -p "$T/dl/proj" "$T/dl/outside/src" "$T/dl/inside/src"
cp "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/dl/outside/src/"
ln -s "$T/dl/outside" "$T/dl/proj/vendor"
run "$T/dl/proj"
check 2 "$EC" "a symlinked directory pointing outside the project exits 2 when a check found nothing"
has "symlinked directory" "$OUT" "the symlinked directory is named as the cause"
mkdir -p "$T/dl/proj2/real/src"
cp "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/dl/proj2/real/src/"
ln -s "$T/dl/proj2/real" "$T/dl/proj2/alias"
run "$T/dl/proj2"
check 1 "$EC" "a symlinked directory that stays inside the project is harmless"
lacks "not scanned" "$OUT" "an inner link is not reported as skipped"

# Every path and heading the notes name exists in the tree.
notes="$REPO_ROOT/skills/migrate/general/UPGRADE-NOTES.md"
while IFS= read -r ref; do
  case "$ref" in
    skills/*) check 1 "$(truth test -e "$REPO_ROOT/$ref")" "notes: path exists: $ref" ;;
  esac
done < <(grep -oE "\`[^\`]*\`" "$notes" | tr -d '\`')
check 1 "$(truth grep -q '^## Completing Auth Integration$' "$REPO_ROOT/skills/add/database/typescript/nestjs-drizzle.md")" "notes: nestjs-drizzle heading exists"
check 0 "$(grep -c "nestjs-drizzle.md\` (Step" "$notes")" "notes: no step letter named for the nestjs-drizzle guide"
check 1 "$(truth grep -q '^### Step C ' "$REPO_ROOT/skills/add/database/python/sqlalchemy.md")" "notes: sqlalchemy Step C heading exists"

# A path with spaces works.
mkdir -p "$T/with space/my proj"
cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$T/with space/my proj/"
run "$T/with space/my proj"
check 1 "$EC" "path with spaces: flagged (exit)"
has "src/integrations/database/mongoose-client.ts:35  mongoose-client-promise-retry  high" "$OUT" "path with spaces: relative file:line printed"

# No version filter: a project that records the current version is still flagged.
mkdir -p "$T/ver/.claude"
cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$T/ver/"
printf '{"templatecentral_version":"999.0.0"}\n' > "$T/ver/.claude/harness.json"
printf '<!-- templateCentral: nextjs@6.0.0 -->\n' > "$T/ver/AGENTS.md"
run "$T/ver"
check 1 "$EC" "a recorded current version does not hide a match"

# The default project is the current directory.
OUT=$(cd "$FIXTURES/sqlalchemy-tls-verify/old" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$RUNNER" 2>&1)
EC=$?
check 0 "$EC" "no argument scans the current directory (check level exits 0)"
has "sqlalchemy-tls-verify  check" "$OUT" "no argument: match printed"

# The project is byte-identical before and after a run.
for def in "$DEFECTS"/*.sh; do
  id=$(meta "$def" id)
  d="$T/ro-$id"
  mkdir -p "$d"
  cp -R "$FIXTURES/$id/old/." "$d/"
  before=$(sig "$d")
  run "$d"
  after=$(sig "$d")
  check "$before" "$after" "$id: project is byte-identical after a run"
done

# Exit codes.
run "$FIXTURES/mongoose-client-promise-retry/old"
check 1 "$EC" "exit 1 when a high level check matched"
run "$FIXTURES/sqlalchemy-tls-verify/old"
check 0 "$EC" "exit 0 when only a check level matched"
has "sqlalchemy-tls-verify" "$OUT" "check level matches are still printed"
run "$T/empty"
check 0 "$EC" "exit 0 when nothing matched"
run "$T/does-not-exist"
check 2 "$EC" "exit 2 for a missing directory"
has "not a directory" "$OUT" "bad directory names the cause"
run "$T/empty" --bogus
check 2 "$EC" "exit 2 for an unknown option"
run "$T/empty" "$T/empty"
check 2 "$EC" "exit 2 for two directories"
printf 'x\n' > "$T/afile"
run "$T/afile"
check 2 "$EC" "exit 2 for a file argument"

# A broken check file fails closed.
cp -R "$REPO_ROOT/skills/migrate/general" "$T/gen"
printf 'id=broken\nlevel=bogus\nnames=x\ntemplate=t\ndesc=d\nfix=f\ncheck() { :; }\n' > "$T/gen/defects/broken.sh"
OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$T/gen/defect-report.sh" "$T/empty" 2>&1)
check 2 "$?" "a check file with a bad level makes the run exit 2"
has "bad level" "$OUT" "bad level is named"
rm -f "$T/gen/defects/broken.sh"
printf 'id=partial\nlevel=high\n' > "$T/gen/defects/partial.sh"
OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$T/gen/defect-report.sh" "$T/empty" 2>&1)
check 2 "$?" "an incomplete check file makes the run exit 2"

# Neutral wording: no alarm words in the messages or the notes.
all=$(cat "$DEFECTS"/*.sh "$REPO_ROOT/skills/migrate/general/UPGRADE-NOTES.md")
for word in vulnerab critical exploit; do
  lacks "$word" "$(printf '%s' "$all" | tr '[:upper:]' '[:lower:]')" "wording stays neutral: no '$word'"
done

echo "defect-report.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

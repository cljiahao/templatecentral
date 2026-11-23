#!/usr/bin/env bash
# Workaround detector: check-workarounds.sh [base-ref]. Looks only at what this change adds or removes, never at code that was already there.
# 1. Added lines that silence a tool (lint, type, coverage, sonar markers, skipped tests, "as any").
# 2. Test files this change removes while the source they cover is still in the tree.
# No waiver file and no allow comment exist: fix the cause, or change the rule in config in its own reviewed change.
set -uo pipefail

arg=${1:-}
arg=${arg#refs/heads/}
head=$(git rev-parse --verify -q 'HEAD^{commit}') || { echo "check-workarounds: no commit yet; nothing to compare. Commit first, then push."; exit 0; }

base=""
if [ -n "$arg" ]; then
  git rev-parse --verify -q "$arg^{commit}" > /dev/null || { echo "check-workarounds: base '$arg' not found. Fetch with full history (fetch-depth 0) and run again." >&2; exit 1; }
  base=$arg
else
  for cand in '@{upstream}' origin/HEAD origin/main origin/master main master; do
    rev=$(git rev-parse --verify -q "$cand^{commit}" 2> /dev/null) || continue
    if [ "$rev" != "$head" ]; then base=$cand; break; fi
  done
fi
if [ -n "$base" ]; then
  from=$(git merge-base "$base" HEAD) || { echo "check-workarounds: no common history with '$base'. Fetch with full history (fetch-depth 0) and run again." >&2; exit 1; }
else
  from=$(git hash-object -t tree /dev/null)
fi

wd=$(mktemp -d "${TMPDIR:-/tmp}/workarounds.XXXXXX") || { echo "check-workarounds: cannot create a temporary directory" >&2; exit 1; }
trap 'rm -rf "$wd"' EXIT

git diff -U0 --no-color -M "$from" HEAD -- '*.py' '*.pyi' '*.ts' '*.tsx' '*.mts' '*.cts' '*.js' '*.jsx' '*.mjs' '*.cjs' > "$wd/added.diff" || { echo "check-workarounds: git diff failed" >&2; exit 1; }

cat > "$wd/scan.awk" <<'AWK'
function report(m) {
  t = substr($0, 2)
  sub(/^[ \t]+/, "", t)
  if (length(t) > 100) t = substr(t, 1, 100) "..."
  printf "%s:%d: %s: %s\n", file, line, m, t
  found = 1
}
/^\+\+\+ / {
  file = substr($0, 7)
  scan = 1
  if (file ~ /^\.claude\// || file ~ /(^|\/)eslint[.]config[.]/) scan = 0
  py = (file ~ /[.]pyi?$/)
  next
}
/^@@/ {
  s = $3
  sub(/^\+/, "", s)
  sub(/,.*/, "", s)
  line = s + 0
  next
}
/^\+/ {
  if (scan) {
    n = tolower(substr($0, 2))
    gsub(/[ \t]+/, " ", n)
    if (n ~ /(#|\/\/|\/\*|^ ?\*).*nosonar/) report("NOSONAR")
    else if (py) {
      if (n ~ /#[ ]?noqa/) report("# noqa")
      else if (n ~ /#[ ]?type:[ ]?ignore/) report("# type: ignore")
      else if (n ~ /pyright:[ ]?ignore/) report("# pyright: ignore")
      else if (n ~ /#[ ]?pylint:[ ]?disable/) report("# pylint: disable")
      else if (n ~ /#[ ]?nosec/) report("# nosec")
      else if (n ~ /pragma:[ ]?no cover/) report("# pragma: no cover")
      else if (n ~ /@pytest[.]mark[.](skip|skipif|xfail)([^a-z0-9_]|$)/) report("@pytest.mark.skip / skipif / xfail")
      else if (n ~ /pytest[.](skip|xfail)\(/) report("pytest.skip( / pytest.xfail(")
    } else {
      if (index(n, "eslint-disable")) report("eslint-disable")
      else if (index(n, "@ts-ignore")) report("@ts-ignore")
      else if (index(n, "@ts-expect-error")) report("@ts-expect-error")
      else if (index(n, "@ts-nocheck")) report("@ts-nocheck")
      else if (index(n, "istanbul ignore")) report("istanbul ignore")
      else if (index(n, "v8 ignore")) report("v8 ignore")
      else if (index(n, "c8 ignore")) report("c8 ignore")
      else if (n ~ /[.](skip|skipif|only)[.(]/) report(".skip( / .skipIf( / .only(")
      else if (n ~ /[.]todo\(/) report(".todo(")
      else if (n ~ /(^|[^a-z0-9_.$])(xit|xdescribe|xtest|fit|fdescribe)\(/) report("xit( / xdescribe( / xtest( / fit( / fdescribe(")
      else if (n ~ /[^a-z0-9_$]as any([^a-z0-9_]|$)/) report("as any")
      else if (n ~ /(^|[^a-z0-9_$>)\]])<any>[a-z0-9_$"']/) report("<any> cast")
    }
  }
  line++
}
END { exit found ? 1 : 0 }
AWK

status=0
if ! awk -f "$wd/scan.awk" "$wd/added.diff" > "$wd/markers.txt"; then
  cat "$wd/markers.txt"
  echo "check-workarounds: this change adds the markers listed above, each one silences a tool instead of fixing the cause." >&2
  echo "Fix the cause. If the rule is wrong for the whole project, change the rule in config (eslint.config, pyproject.toml, vitest or vite config) in its own reviewed change." >&2
  status=1
fi

git diff --name-only --no-color -M --diff-filter=D "$from" HEAD > "$wd/deleted.txt" || { echo "check-workarounds: git diff failed" >&2; exit 1; }
git ls-files > "$wd/tree.txt" || { echo "check-workarounds: git ls-files failed" >&2; exit 1; }
: > "$wd/orphans.txt"
while IFS= read -r f || [ -n "$f" ]; do
  name=${f##*/}
  case "$name" in
    *.test.ts | *.test.tsx | *.test.js | *.test.jsx | *.spec.ts | *.spec.tsx | *.spec.js | *.spec.jsx | *.e2e-spec.ts)
      stem=${name%.*}
      stem=${stem%.test}
      stem=${stem%.spec}
      stem=${stem%.e2e-spec}
      ext=${name##*.}
      ;;
    test_*.py)
      stem=${name#test_}
      stem=${stem%.py}
      ext=py
      ;;
    *_test.py)
      stem=${name%_test.py}
      ext=py
      ;;
    *) continue ;;
  esac
  case "$ext" in
    ts | tsx) pat="/${stem}[.](ts|tsx)$" ;;
    js | jsx) pat="/${stem}[.](js|jsx)$" ;;
    *) pat="/${stem}[.]py$" ;;
  esac
  src=$(sed 's@^@/@' "$wd/tree.txt" | grep -E "$pat" | grep -vE '(^|/)(test|tests|__tests__)/|[.](test|spec)[.]|/test_|_test[.]py$' | head -n 1)
  if [ -n "$src" ]; then
    printf '%s (covers %s)\n' "$f" "${src#/}" >> "$wd/orphans.txt"
  fi
done < "$wd/deleted.txt"
if [ -s "$wd/orphans.txt" ]; then
  while IFS= read -r l; do printf 'removed test: %s\n' "$l"; done < "$wd/orphans.txt"
  echo "check-workarounds: this change deletes the test files listed above while the source they cover is still in the tree." >&2
  echo "Restore the test file, or remove the source it covers in the same change." >&2
  status=1
fi

if [ "$status" -eq 0 ]; then echo "check-workarounds: no suppression markers added and no covering tests removed"; fi
exit "$status"

#!/usr/bin/env bash
# Deterministic scaffold-config validator.
# Checks the files in skills/scaffold/<stack>/template/ themselves: every *.json with jq (JSONC
# comments stripped first, by a string-aware pass that keeps URLs like "https://..." intact) and
# every *.js, *.mjs and *.cjs with `node --check` (the nearest package.json decides how a .js file
# loads). The shared template-settings-ts and template-settings-py trees are checked the same way
# and must each hold a settings.json.
# Reports every malformed file and exits 1, so a broken scaffold config template is caught
# by a PR check, not only by the optional monthly LLM scaffold-verify cron. Exits 1 when nothing
# at all was validated, or when a stack's template.manifest has no JSON or JS file under its template/.
# No `set -e`: a failing file is reported and the loop continues to the next one.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "validate-scaffold-configs: jq not found" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "validate-scaffold-configs: node not found" >&2; exit 2; }

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root" || exit 2

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# String-aware JSONC comment stripper — preserves // and /* inside string literals.
strip_jsonc() {
  node -e '
    const s=require("fs").readFileSync(0,"utf8");let o="",i=0,st=false,esc=false;
    while(i<s.length){const c=s[i],n=s[i+1];
      if(st){o+=c;if(esc)esc=false;else if(c==="\\")esc=true;else if(c==="\"")st=false;i++;continue;}
      if(c==="\""){st=true;o+=c;i++;continue;}
      if(c==="/"&&n==="/"){while(i<s.length&&s[i]!=="\n")i++;continue;}
      if(c==="/"&&n==="*"){i+=2;while(i<s.length&&!(s[i]==="*"&&s[i+1]==="/"))i++;i+=2;continue;}
      o+=c;i++;}
    process.stdout.write(o);' 2>/dev/null
}

fail=0
total=0

# Template trees: the files are real, so they are checked directly.
for tree in skills/scaffold/*/template skills/scaffold/shared/template-settings-*; do
  [ -d "$tree" ] || continue
  while IFS= read -r file; do
    total=$((total + 1))
    case "$file" in
      *.json)
        if strip_jsonc < "$file" | jq empty >/dev/null 2>&1; then
          echo "  ok    $file"
        else
          echo "  FAIL  $file  — invalid JSON" >&2
          strip_jsonc < "$file" | jq empty 2>&1 | sed 's/^/          /' >&2
          fail=1
        fi ;;
      *)
        err="$workdir/node_check_err"
        if node --check "$file" >/dev/null 2>"$err"; then
          echo "  ok    $file"
        else
          echo "  FAIL  $file  — invalid JS" >&2
          sed 's/^/          /' "$err" >&2
          fail=1
        fi
        rm -f "$err" ;;
    esac
  done < <(find "$tree" -type f \( -name '*.json' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) | LC_ALL=C sort)
done

# A stack with a template.manifest must have JSON or JS template files to validate, so deleting or
# renaming its template/ tree cannot pass on the other stacks' files.
for manifest in skills/scaffold/*/template.manifest; do
  [ -f "$manifest" ] || continue
  stack_dir=$(dirname "$manifest")
  case "$stack_dir" in */shared) continue ;; esac
  n=$(find "$stack_dir/template" -type f \( -name '*.json' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -eq 0 ]; then
    echo "  FAIL  $stack_dir  — template.manifest exists but template/ holds no JSON or JS file to validate" >&2
    fail=1
  fi
done

# The two settings.json bodies are JSON that Claude Code reads at the start of every session, so each
# settings tree must exist and hold a JSON file to validate.
for variant in ts py; do
  n=$(find "skills/scaffold/shared/template-settings-$variant" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -eq 0 ]; then
    echo "  FAIL  skills/scaffold/shared/template-settings-$variant  — no settings.json to validate" >&2
    fail=1
  fi
done

if [ "$total" -eq 0 ]; then
  echo "validate-scaffold-configs: no template file was found, so nothing was validated." >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  echo "validate-scaffold-configs: one or more scaffold config templates are malformed." >&2
  exit 1
fi
echo "validate-scaffold-configs: all $total JSON/JS template files valid."

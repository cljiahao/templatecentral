#!/usr/bin/env bash
# Deterministic scaffold-config validator.
# Extracts every ```json fenced block from skills/scaffold/*/config-files.md (package.json,
# tsconfig.json, settings-style configs, ...) and validates each as JSON with jq. tsconfig-style
# blocks are JSONC, so a string-aware pass strips // and /* */ comments first (URLs like
# "https://..." are preserved). Fails (exit 1) on the first malformed block so a broken scaffold
# config template is caught by a PR check, not only by the optional monthly LLM scaffold-verify cron.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "validate-scaffold-configs: jq not found" >&2; exit 2; }

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root" || exit 2

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# String-aware JSONC comment stripper — preserves // and /* inside string literals.
strip_jsonc() {
  if command -v node >/dev/null 2>&1; then
    node -e '
      const s=require("fs").readFileSync(0,"utf8");let o="",i=0,st=false,esc=false;
      while(i<s.length){const c=s[i],n=s[i+1];
        if(st){o+=c;if(esc)esc=false;else if(c==="\\")esc=true;else if(c==="\"")st=false;i++;continue;}
        if(c==="\""){st=true;o+=c;i++;continue;}
        if(c==="/"&&n==="/"){while(i<s.length&&s[i]!=="\n")i++;continue;}
        if(c==="/"&&n==="*"){i+=2;while(i<s.length&&!(s[i]==="*"&&s[i+1]==="/"))i++;i+=2;continue;}
        o+=c;i++;}
      process.stdout.write(o);' 2>/dev/null
  else
    # Fallback: drop whole-line // comments and trailing " //" comments, never touching "://".
    sed -E 's@([^:])//[^"]*$@\1@; /^[[:space:]]*\/\//d'
  fi
}

fail=0
total=0

for f in skills/scaffold/*/config-files.md; do
  [ -f "$f" ] || continue
  # Split each ```json ... ``` block into its own file named by its start line.
  rm -f "$workdir"/*.json 2>/dev/null || true
  awk -v dir="$workdir" '
    /^```json[[:space:]]*$/ { inblk=1; start=NR; out=dir "/" NR ".json"; next }
    inblk && /^```[[:space:]]*$/ { close(out); inblk=0; next }
    inblk { print > out }
  ' "$f"

  for blk in "$workdir"/*.json; do
    [ -e "$blk" ] || continue
    total=$((total + 1))
    line=$(basename "$blk" .json)
    if strip_jsonc < "$blk" | jq empty >/dev/null 2>&1; then
      echo "  ok    $f:$line"
    else
      echo "  FAIL  $f:$line  — invalid JSON fence" >&2
      strip_jsonc < "$blk" | jq empty 2>&1 | sed 's/^/          /' >&2
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  echo "validate-scaffold-configs: one or more scaffold JSON config templates are malformed." >&2
  exit 1
fi
echo "validate-scaffold-configs: all $total JSON config fences valid."

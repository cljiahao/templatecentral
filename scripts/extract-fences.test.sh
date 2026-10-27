#!/usr/bin/env bash
# scripts/extract-fences.test.sh — tests for scripts/extract-fences.py.
# Usage: bash scripts/extract-fences.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRACT="$REPO_ROOT/scripts/extract-fences.py"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

ok_if() { # ok_if <description> <command...> — pass when the command succeeds
  local desc="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $desc"; fi
}

fence='```'

# extracts_heading_fence
cat > "$T/a.md" <<MD
**\`a/b.json\`**
${fence}json
{"k": 1}
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o1" --src "$T/a.md" > "$T/o1.out" 2> "$T/o1.err"
check '{"k": 1}' "$(cat "$T/o1/b.json" 2>/dev/null)" "extracts_heading_fence: body"
want=$(printf '{"k": 1}\n' | shasum -a 256 | cut -d' ' -f1)
check "$want  b.json" "$(cat "$T/o1.out")" "extracts_heading_fence: stdout line"

# stack-style heading keeps the directory
cat > "$T/s.md" <<MD
### \`src/x.ts\`

${fence}ts
export const x = 1;
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o1b" --src "$T/s.md" > /dev/null 2>&1
check 'export const x = 1;' "$(cat "$T/o1b/x.ts" 2>/dev/null)" "extracts_heading_fence: ### heading"

# skips_unheaded_fence
cat > "$T/b.md" <<MD
Run this:
${fence}bash
pnpm install
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o2" --src "$T/b.md" > "$T/o2.out" 2> "$T/o2.err"
check "" "$(cat "$T/o2.out")" "skips_unheaded_fence: no stdout"
case "$(cat "$T/o2.err")" in
  "skipped $T/b.md:2 "*) PASS=$((PASS + 1)) ;;
  *) FAIL=$((FAIL + 1)); echo "FAIL: skips_unheaded_fence: stderr [$(cat "$T/o2.err")]" ;;
esac

# a shell command block under a script heading is not a script
cat > "$T/c.md" <<MD
**\`.claude/hooks/h.sh\`**
${fence}bash
chmod +x .claude/hooks/h.sh
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o2b" --src "$T/c.md" > "$T/o2b.out" 2> "$T/o2b.err"
check "" "$(cat "$T/o2b.out")" "skips_unheaded_fence: command under script heading"
ok_if "command block logged as skipped" grep -q '^skipped ' "$T/o2b.err"

# variant_naming
cat > "$T/v.md" <<MD
**\`.claude/hooks/hook.sh\`** (canonical):

**For TS stacks:**
${fence}bash
#!/usr/bin/env bash
echo ts
${fence}

**For FastAPI:**
${fence}bash
#!/usr/bin/env bash
echo py
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o3" --src "$T/v.md" > /dev/null 2>&1
check "echo ts" "$(sed -n 2p "$T/o3/hook.ts.sh" 2>/dev/null)" "variant_naming: hook.ts.sh"
check "echo py" "$(sed -n 2p "$T/o3/hook.py.sh" 2>/dev/null)" "variant_naming: hook.py.sh"

# unterminated fence is a parse error
printf '%s\n%s\n{\n' "**\`a.json\`**" "${fence}json" > "$T/bad.md"
python3 "$EXTRACT" --flat --out "$T/o4" --src "$T/bad.md" > /dev/null 2>&1
check 2 $? "parse error exits 2"

# stack mode: variant filtering, CI host selection, fastapi quality-job composition
for combo in nextjs:github nextjs:azure fastapi:github fastapi:azure nestjs:github vite-react:azure; do
  stack=${combo%%:*}; ci=${combo##*:}
  python3 "$EXTRACT" --stack "$stack" --ci "$ci" --out "$T/st-$combo" > "$T/st-$combo.out" 2> "$T/st-$combo.err"
  check 0 $? "stack $combo exits 0"
  ok_if "stack $combo wrote output" test -s "$T/st-$combo.out"
done
ok_if "github combo has ci.yml" test -f "$T/st-nextjs:github/.github/workflows/ci.yml"
ok_if "github combo has no azure pipeline" test ! -e "$T/st-nextjs:github/azure-pipelines"
ok_if "azure combo has the gates template" test -f "$T/st-nextjs:azure/azure-pipelines/templatecentral-gates.yml"
ok_if "azure combo has no github workflow" test ! -e "$T/st-nextjs:azure/.github"
ok_if "fastapi ci.yml carries the pyright quality job" grep -q 'pyright' "$T/st-fastapi:github/.github/workflows/ci.yml"
ok_if "fastapi ci.yml keeps the shared changelog job" grep -q '^  changelog:' "$T/st-fastapi:github/.github/workflows/ci.yml"
ok_if "fastapi gets the py hook" test -f "$T/st-fastapi:github/.claude/hooks/user-prompt-guard.py"
ok_if "fastapi does not get the cjs hook" test ! -e "$T/st-fastapi:github/.claude/hooks/user-prompt-guard.cjs"
ok_if "nextjs gets the cjs hook" test -f "$T/st-nextjs:github/.claude/hooks/user-prompt-guard.cjs"
ok_if "nextjs does not get the py hook" test ! -e "$T/st-nextjs:github/.claude/hooks/user-prompt-guard.py"

# same_as_test_harness_kit: hook bytes match the original hook-only extractor
cat > "$T/legacy.py" <<'PY'
import os, re, sys
out, srcs = sys.argv[1], sys.argv[2:]
heading = re.compile(r"^\*\*`([^`]+\.(?:sh|cjs|py))`\*\*")
for src in srcs:
    lines = open(src, encoding="utf-8").read().split("\n")
    path = variant = None
    i = 0
    while i < len(lines):
        line = lines[i]
        m = heading.match(line)
        if m:
            path, variant = m.group(1), None
        elif line.startswith("**For TS"):
            variant = "ts"
        elif line.startswith("**For FastAPI"):
            variant = "py"
        elif line.startswith("```") and len(line) > 3:
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            body = lines[i + 1:j]
            if path and body and (not path.endswith(".sh") or body[0].startswith("#!")):
                stem, ext = os.path.splitext(os.path.basename(path))
                name = stem + ("." + variant if variant else "") + ext
                open(os.path.join(out, name), "w", encoding="utf-8").write("\n".join(body) + "\n")
                if not variant:
                    path = None
            i = j
        i += 1
PY
mkdir -p "$T/legacy-out"
python3 "$T/legacy.py" "$T/legacy-out" "$REPO_ROOT"/skills/scaffold/shared/harness-kit*.md
python3 "$EXTRACT" --flat --ext sh,cjs,py --out "$T/new-out" --src "$REPO_ROOT"/skills/scaffold/shared/harness-kit*.md > /dev/null 2>&1
check "" "$(diff -r "$T/legacy-out" "$T/new-out" 2>&1)" "same_as_test_harness_kit: identical hook files"
check "true" "$([[ -n "$(ls "$T/new-out")" ]] && echo true || echo false)" "same_as_test_harness_kit: non-empty"

echo "extract-fences.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

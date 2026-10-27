#!/usr/bin/env bash
# scripts/extract-fences.test.sh — tests for scripts/extract-fences.py.
# Usage: bash scripts/extract-fences.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRACT="${EXTRACT_FENCES:-$REPO_ROOT/scripts/extract-fences.py}"
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
# The CI files and the per-stack hooks moved into the template trees; the extractor must not
# produce them any more (check-golden.sh fails a path produced by both), and the trees must hold them.
TPL="$REPO_ROOT/skills/scaffold/shared"
ok_if "extractor no longer writes ci.yml (github)" test ! -e "$T/st-nextjs:github/.github/workflows/ci.yml"
ok_if "extractor no longer writes the gates template (azure)" test ! -e "$T/st-nextjs:azure/azure-pipelines/templatecentral-gates.yml"
ok_if "extractor no longer writes the hooks" test ! -e "$T/st-fastapi:github/.claude/hooks/user-prompt-guard.py" -a ! -e "$T/st-nextjs:github/.claude/hooks/user-prompt-guard.cjs"
ok_if "github TS template has ci.yml" test -f "$TPL/template-ci/github-ts/.github/workflows/ci.yml"
ok_if "github template has no azure pipeline" test ! -e "$TPL/template-ci/github-ts/azure-pipelines" -a ! -e "$TPL/template-ci/github-py/azure-pipelines"
ok_if "azure template has the gates template" test -f "$TPL/template-ci/azure/azure-pipelines/templatecentral-gates.yml"
ok_if "azure template has no github workflow" test ! -e "$TPL/template-ci/azure/.github"
ok_if "fastapi ci.yml carries the pyright quality job" grep -q 'pyright' "$TPL/template-ci/github-py/.github/workflows/ci.yml"
ok_if "fastapi ci.yml keeps the shared changelog job" grep -q '^  changelog:' "$TPL/template-ci/github-py/.github/workflows/ci.yml"
ok_if "fastapi gets the py hook" test -f "$TPL/template-py/.claude/hooks/user-prompt-guard.py"
ok_if "fastapi does not get the cjs hook" test ! -e "$TPL/template-py/.claude/hooks/user-prompt-guard.cjs"
ok_if "nextjs gets the cjs hook" test -f "$TPL/template-ts/.claude/hooks/user-prompt-guard.cjs"
ok_if "nextjs does not get the py hook" test ! -e "$TPL/template-ts/.claude/hooks/user-prompt-guard.py"

# bare_opener_extracted: an untagged fence is a fence
cat > "$T/bare.md" <<MD
**\`.gitignore\`**
${fence}
node_modules
.env
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o5" --src "$T/bare.md" > /dev/null 2>&1
check "node_modules" "$(sed -n 1p "$T/o5/.gitignore" 2>/dev/null)" "bare_opener_extracted"

# stale_path_not_attached: a skipped command fence consumes the heading; a later bare fence is unheaded
cat > "$T/stale.md" <<MD
**\`.claude/hooks/h.sh\`**
${fence}bash
chmod +x .claude/hooks/h.sh
${fence}

Unrelated output:
${fence}
README: 1 created
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o6" --src "$T/stale.md" > "$T/o6.out" 2> /dev/null
check "" "$(cat "$T/o6.out")" "stale_path_not_attached"

# tilde_fence_not_closed_by_backticks
cat > "$T/tilde.md" <<MD
**\`a/SKILL.md\`**:
~~~markdown
# Title
${fence}bash
echo inner
${fence}
tail line
~~~
MD
python3 "$EXTRACT" --flat --out "$T/o7" --src "$T/tilde.md" > /dev/null 2>&1
check "tail line" "$(tail -1 "$T/o7/SKILL.md" 2>/dev/null)" "tilde_fence_not_closed_by_backticks"

# longer_fence_not_closed_by_shorter
cat > "$T/long.md" <<MD
### \`AGENTS.md\`

\`\`\`\`markdown
# Agents
${fence}bash
echo inner
${fence}
last line
\`\`\`\`
MD
python3 "$EXTRACT" --flat --out "$T/o8" --src "$T/long.md" > /dev/null 2>&1
check "last line" "$(tail -1 "$T/o8/AGENTS.md" 2>/dev/null)" "longer_fence_not_closed_by_shorter"

# nested_snippet_stays_in_outer_fence: a tagged ${fence} block inside a ${fence} block does not end it
cat > "$T/nest.md" <<MD
Create \`.claude/skills/x/SKILL.md\`:

${fence}markdown
# Skill
${fence}bash
pnpm check
${fence}
Report failures.
${fence}

Create \`CLAUDE.md\` with one line:

${fence}
@AGENTS.md
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o12" --src "$T/nest.md" > /dev/null 2>&1
check "Report failures." "$(tail -1 "$T/o12/SKILL.md" 2>/dev/null)" "nested_snippet_stays_in_outer_fence"
check "@AGENTS.md" "$(cat "$T/o12/CLAUDE.md" 2>/dev/null)" "nested_snippet_does_not_swallow_next_fence"

# create_heading_lang_mismatch_fails: a "Create `x.json`:" line over a bash fence is not that file
cat > "$T/mm.md" <<MD
Create \`config.json\`:

${fence}bash
pnpm install
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o13" --src "$T/mm.md" > /dev/null 2> "$T/o13.err"
check 2 $? "create_heading_lang_mismatch_fails: exit"
case "$(cat "$T/o13.err")" in *"$T/mm.md:3"*config.json*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: mismatch error names location [$(cat "$T/o13.err")]" ;; esac

# extensionless names and directory paths
cat > "$T/noext.md" <<MD
### \`Makefile\`

${fence}make
all:
${fence}

### \`.husky/pre-commit\`

${fence}sh
echo hi
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o9" --src "$T/noext.md" > /dev/null 2>&1
check "all:" "$(cat "$T/o9/Makefile" 2>/dev/null)" "extensionless_makefile"
check "echo hi" "$(cat "$T/o9/pre-commit" 2>/dev/null)" "extensionless_path_with_dir"

# empty_file_heading: a heading described as an empty file is a 0-byte file
cat > "$T/empty.md" <<MD
### \`src/schemas/index.ts\`

Empty file — placeholder.

### \`src/other.ts\`

${fence}ts
export {};
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o10" --src "$T/empty.md" > /dev/null 2>&1
check "0" "$(wc -c < "$T/o10/index.ts" 2>/dev/null | tr -d ' ')" "empty_file_heading"

# prose_create: "Create \`path\` ...:" before a fence
cat > "$T/prose.md" <<MD
### 6. Write project AGENTS.md

Create \`AGENTS.md\` at the project root with this exact content (fill in \`[Project Name]\`):

${fence}markdown
# AGENTS.md — [Project Name]
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/o11" --src "$T/prose.md" > /dev/null 2>&1
check "# AGENTS.md — [Project Name]" "$(cat "$T/o11/AGENTS.md" 2>/dev/null)" "prose_create"

# coverage: every path heading yields a file, except the entries in tests/golden/unfenced.txt
want_unfenced=$(grep -v '^#' "$REPO_ROOT/tests/golden/unfenced.txt" | sed 's/ *#.*//' | grep . | LC_ALL=C sort)
for combo in nextjs:github nextjs:azure vite-react:github vite-react:azure fastapi:github fastapi:azure nestjs:github nestjs:azure; do
  stack=${combo%%:*}; ci=${combo##*:}
  python3 "$EXTRACT" --stack "$stack" --ci "$ci" --out "$T/cov-$combo" > /dev/null 2> "$T/cov-$combo.err"
  got=$(grep '^unfenced ' "$T/cov-$combo.err" | sed -E 's/^unfenced ([^:]+):[0-9]+ (.*)$/\1 \2/' | LC_ALL=C sort)
  check "$want_unfenced" "$got" "coverage $combo: path headings without a file match tests/golden/unfenced.txt"
done

# pinned_inline_variants: the Step A body in the variant kits is the golden settings.json
python3 "$EXTRACT" --flat --out "$T/flat-ts" --src "$REPO_ROOT/skills/scaffold/shared/harness-kit-ts.md" > /dev/null 2>&1
python3 "$EXTRACT" --flat --out "$T/flat-py" --src "$REPO_ROOT/skills/scaffold/shared/harness-kit-fastapi.md" > /dev/null 2>&1
check "" "$(diff "$T/flat-ts/settings.ts.json" "$T/cov-nextjs:github/.claude/settings.json" 2>&1)" "pinned_inline_variants: ts settings.json"
check "" "$(diff "$T/flat-py/settings.py.json" "$T/cov-fastapi:github/.claude/settings.json" 2>&1)" "pinned_inline_variants: fastapi settings.json"

# pointer_closes_heading: a line that points at a moved template file ends the heading before it,
# so a later bare fence is not read as that heading's file
cat > "$T/ptr.md" <<MD
**\`.claude/settings.json\`** — rules heading with no body here.

\`.claude/hooks/x.sh\` is a hook. Step 0 copies it from \`<skill-dir>/shared/template/.claude/hooks/x.sh\`.

${fence}bash
chmod +x .claude/hooks/*.sh
${fence}
MD
python3 "$EXTRACT" --flat --out "$T/optr" --src "$T/ptr.md" > "$T/optr.out" 2> "$T/optr.err"
check "" "$(cat "$T/optr.out")" "pointer_closes_heading: no file written"
check "1" "$(grep -c '^skipped .*no path heading' "$T/optr.err")" "pointer_closes_heading: the chmod fence has no heading"
check "1" "$(grep -c '^unfenced .* .claude/settings.json' "$T/optr.err")" "pointer_closes_heading: the open heading is reported unfenced"

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
cat > "$T/kit.md" <<MD
**\`.claude/hooks/a.sh\`** (hook):

**For TS stacks — uses node:**
${fence}bash
#!/usr/bin/env bash
echo ts
${fence}

**For FastAPI — uses python3:**
${fence}bash
#!/usr/bin/env bash
echo py
${fence}

**\`.claude/hooks/b.cjs\`** (TS only):
${fence}javascript
console.log(1);
${fence}

**\`.claude/hooks/c.py\`** (FastAPI only):
${fence}python
print(1)
${fence}

**\`.claude/hooks/d.sh\`**:
${fence}bash
#!/usr/bin/env bash
echo d
${fence}
MD
mkdir -p "$T/legacy-out"
python3 "$T/legacy.py" "$T/legacy-out" "$T/kit.md"
python3 "$EXTRACT" --flat --ext sh,cjs,py --out "$T/new-out" --src "$T/kit.md" > /dev/null 2>&1
check "" "$(diff -r "$T/legacy-out" "$T/new-out" 2>&1)" "same_as_test_harness_kit: identical hook files"
check "5" "$(find "$T/new-out" -type f | wc -l | tr -d ' ')" "same_as_test_harness_kit: every hook extracted"

echo "extract-fences.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

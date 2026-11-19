#!/usr/bin/env bash
# scripts/check-versions.test.sh — check-versions.sh passes on a copy of the repo and fails on each planted drift.
# Every mutation must change the copy: a sed pattern that no longer matches would otherwise pass silently.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d "${TMPDIR:-/tmp}/cv.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
base="$T/base"; mkdir -p "$base/scripts"
cp -R "$REPO/skills" "$base/skills"
[[ -d "$REPO/.github" ]] && cp -R "$REPO/.github" "$base/.github"
[[ -d "$REPO/.claude/rules" ]] && { mkdir -p "$base/.claude"; cp -R "$REPO/.claude/rules" "$base/.claude/rules"; }
cp "$REPO/scripts/deploy-smoke.sh" "$base/scripts/"
for f in AGENTS.md README.md; do [[ -f "$REPO/$f" ]] && cp "$REPO/$f" "$base/$f"; done
# sub <file> <sed expression>: portable in-place edit (BSD and GNU), no backup file left behind.
sub() { sed "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }
t() { # t <name> <want rc> <mutation run inside the copy> [msg fragment the output must contain]
  local w="$T/$1"; cp -R "$base" "$w"
  (cd "$w" && eval "$3") >/dev/null 2>&1
  if [[ "$3" != "true" ]] && diff -rq "$base" "$w" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1)); echo "FAIL: $1 — the mutation changed nothing (pattern no longer matches)"; rm -rf "$w"; return
  fi
  local out; out=$(bash "$REPO/scripts/check-versions.sh" --root "$w" 2>&1); local rc=$?
  if [[ $rc -ne $2 ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — want rc $2, got $rc"
  elif [[ -n "${4:-}" && "$out" != *"$4"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — output lacks '$4': $out"
  else PASS=$((PASS + 1)); fi
  rm -rf "$w"
}
V=skills/scaffold/shared/versions.txt
NJ=skills/scaffold/nextjs/template/package.json
VR=skills/scaffold/vite-react/template/package.json
NS=skills/scaffold/nestjs/template/package.json
CI=skills/scaffold/shared/template-ci/github-ts/.github/workflows/ci.yml
CIPY=skills/scaffold/shared/template-ci/github-py/.github/workflows/ci.yml
DOC=skills/add/test/nextjs.md
t baseline 0 true "check-versions: ok"
t npm_spec_drift 1 "sub $NJ 's/\"vitest\": \"[^\"]*\"/\"vitest\": \"^1.0.0\"/'" "vitest is ^1.0.0"
t pnpm_drift 1 "sub $NJ 's/pnpm@[0-9.]*/pnpm@1.0.0/'" "packageManager is pnpm@1.0.0"
t types_node_drift 1 "sub $NJ 's/\"@types\\/node\": \"[^\"]*\"/\"@types\\/node\": \"^1\"/'" "@types/node is ^1"
t unlisted_dependency 1 "sub $NJ 's/\"vitest\":/\"left-pad\": \"^1.0.0\", \"vitest\":/'" "left-pad is not listed"
t action_sha_drift 1 "sub $CI 's/checkout@[0-9a-f]\\{40\\}/checkout@0000000000000000000000000000000000000000/'" "actions/checkout@000000000000"
t action_tag_drift 1 "sub $CI 's/# v7\\.0\\.1/# v0.0.1/'" "# v0.0.1"
t tool_variable_drift 1 "sub $CI 's/DIFF_COVER_VERSION: \"[^\"]*\"/DIFF_COVER_VERSION: \"0.0.1\"/'" "DIFF_COVER_VERSION is 0.0.1"
t node_version_drift 1 "sub $CI 's/node-version: \"[0-9][0-9]*\"/node-version: \"1\"/'" "Node 1 but"
t gitleaks_drift 1 "sub skills/scaffold/shared/template/.claude/ci-gates.sh 's/GITLEAKS_VERSION=\"[^\"]*\"/GITLEAKS_VERSION=\"0.0.1\"/'" "GITLEAKS_VERSION is 0.0.1"
t pip_requirement_drift 1 "sub skills/scaffold/fastapi/template/requirements-dev.txt 's/^pytest>=.*/pytest>=1.0/'" "pytest is"
t pip_spec_in_prose 1 "printf '\nUse pytest==9.0 here.\n' >> $DOC" "prose states a version for pytest"
t uv_pin_drift_dockerfile 1 "sub skills/scaffold/fastapi/template/Dockerfile 's/uv==0\\.13\\.7/uv==0.13.6/'" "uv==0.13.6 but versions.txt says uv==0.13.7"
t uv_pin_drift_ci 1 "sub skills/scaffold/shared/template-ci/azure-py/azure-pipelines.yml 's/uv==0\\.13\\.7/uv==0.13.6/'" "uv==0.13.6"
t uv_pin_drift_prose 1 "sub skills/scaffold/fastapi/source-files.md 's/uv==0\\.13\\.7/uv==0.13.6/'" "uv==0.13.6"
t uv_pin_trailing_dot_prose 0 "printf '\n# pin uv==0.13.7.\n' >> skills/scaffold/fastapi/template/Dockerfile"
t uv_pin_extra_drift 1 "printf '\nInstall uv[x]==0.13.6 first.\n' >> $DOC" "uv==0.13.6 but versions.txt says uv==0.13.7"
t package_pin_in_prose 1 "printf '\nInstall vitest@4.1.8 first.\n' >> $DOC" "prose states a version for vitest"
# versions.txt itself
t versions_missing 1 "rm $V" "not found"
t versions_empty 1 ": > $V" "no records"
t versions_comments_only 1 "printf '# nothing here\n\n' > $V" "no records"
t versions_duplicate_key 1 "printf 'node major 27\n' >> $V" "duplicate key node major"
t versions_duplicate_identical 1 "printf 'node major 26\n' >> $V" "duplicate key node major"
t versions_duplicate_pnpm 1 "printf 'pnpm 1.0.0\n' >> $V" "duplicate key pnpm"
t versions_malformed 1 "printf 'npm lonelyname\n' >> $V" "unreadable record"
t versions_unknown_kind 1 "printf 'bogus a b\n' >> $V" "unreadable record"
# templates and seeded files
t dockerfile_image_drift 1 "sub skills/scaffold/nextjs/template/Dockerfile 's/node:26-alpine/node:20-alpine/'" "node:20-alpine"
t engines_node_drift 1 "sub $NJ 's/\">=26\\.12\\.1\"/\">=20.0.0\"/'" "engines.node"
t python_ci_version_drift 1 "sub $CIPY 's/python-version: \"3\\.14\"/python-version: \"3.12\"/'" "Python 3.12"
t pyproject_target_drift 1 "sub skills/scaffold/fastapi/template/pyproject.toml 's/target-version = \"py314\"/target-version = \"py312\"/'" "ruff target"
t nestjs_zod_caret_drift 1 "sub $NS 's/\"nestjs-zod\": \"5\\.6\\.0\"/\"nestjs-zod\": \"^5.6.0\"/'" "nestjs-zod"
t testing_library_dom_drift 1 "sub $VR 's/\"@testing-library\\/dom\": \"[^\"]*\"/\"@testing-library\\/dom\": \"^9.0.0\"/'" "@testing-library/dom"
t beanie_python_image_drift 1 "sub skills/add/database/python/beanie.md 's/python:3\\.13\\.16-slim/python:3.13.1-slim/'" "python:3.13.1-slim"
t skill_fence_pip_drift 1 "printf '\n\`\`\`\npip install pytest>=1.0\n\`\`\`\n' >> $DOC" "pytest"
t skill_fence_npm_drift 1 "printf '\n\`\`\`bash\npnpm add vitest@1.0.0\n\`\`\`\n' >> $DOC" "vitest@1.0.0"
t skill_fence_action_drift 1 "printf '\n\`\`\`yaml\n- uses: actions/checkout@v4\n\`\`\`\n' >> $DOC" "actions/checkout"
# prose version rule: below or at the pin passes, above the pin and current/latest claims fail
t prose_floor_below_pin 0 "printf '\nNext.js ≥16.3.8 fixes an advisory.\n' >> $DOC"
t prose_floor_above_pin 1 "printf '\nNext.js ≥99.0 is required.\n' >> $DOC" "prose says Next.js 99.0"
t prose_current_claim 1 "printf '\nNext.js 16.2 is current.\n' >> $DOC" "current/latest"
t prose_latest_claim 1 "printf '\nThe latest FastAPI 0.100 does this.\n' >> $DOC" "current/latest"
t prose_nest_held_stray_major 1 "printf '\nThe stack is Nest 12 here.\n' >> $DOC" "prose says Nest 12"
t prose_nest_held_stray_nestjs 1 "printf '\nRuns NestJS 12 today.\n' >> $DOC" "prose says NestJS 12"
t prose_nest_held_major_ok 0 "printf '\nRuns NestJS 11 today.\n' >> $DOC"
t prose_floor_in_rules 1 "printf '\nReact 99 is the floor.\n' >> .claude/rules/nextjs.md" "prose says React 99"
t prose_floor_in_template_agents 1 "printf '\nPydantic >=99 only.\n' >> skills/scaffold/fastapi/template-agents/AGENTS.md" "prose says Pydantic 99"
# versions.txt: sub-keys and kinds are exact; a BOM or CRLF line ends are fine; one name under pip and npm is legal
t versions_wrong_case_subkey 1 "sed 's/^node   major/node   Major/' $V > $V.new && mv $V.new $V" "unreadable record"
t versions_wrong_case_kind 1 "printf 'Node major 27\n' >> $V" "unreadable record"
t versions_unknown_subkey 1 "printf 'python major 3.14\n' >> $V" "unreadable record"
t versions_unknown_node_subkey 1 "printf 'node patch 1\n' >> $V" "unreadable record"
t versions_same_name_pip_and_npm 0 "printf 'pip next ^1\n' >> $V" "check-versions: ok"
t versions_bom 0 "{ printf '\357\273\277'; cat $V; } > $V.new && mv $V.new $V" "check-versions: ok"
t versions_crlf 0 "awk '{ printf \"%s\\r\\n\", \$0 }' $V > $V.new && mv $V.new $V" "check-versions: ok"
# prose: ordinary words are not products; every spelling of a product name is
t prose_next_20_items 0 "printf '\nReview the next 20 items before merging.\n' >> $DOC" "check-versions: ok"
t prose_next_100_ms 0 "printf '\nWait the next 100 ms.\n' >> $DOC" "check-versions: ok"
t prose_word_boundary 0 "printf '\nSee the next-foo 20 and nextjs-foo 99 helpers.\n' >> $DOC" "check-versions: ok"
t prose_react_sentence_end 0 "printf '\nReact 19 is fine. The latest news.\n' >> $DOC" "check-versions: ok"
t prose_words_between_name_and_number 0 "printf '\nNext.js, at least 99.\n' >> $DOC" "check-versions: ok"
t prose_python_setting_in_code_span 0 "printf '\nSet pyright \`3.14\` here.\n' >> $DOC" "check-versions: ok"
t prose_alias_nextjs_lower 1 "printf '\nnextjs 99 only.\n' >> $DOC" "prose says nextjs 99"
t prose_alias_nextjs_camel 1 "printf '\nNextJS 99 only.\n' >> $DOC" "prose says NextJS 99"
t prose_alias_tailwind 1 "printf '\nTailwind 99 only.\n' >> $DOC" "prose says Tailwind 99"
t prose_bold_name 1 "printf '\n**Next.js** 99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_link_name 1 "printf '\n[Next.js](https://x.example) 99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_table_row 1 "printf '\n| Next.js | 99.4 |\n' >> $DOC" "prose says Next.js 99.4"
t prose_code_span_floor 1 "printf '\nNext.js \`≥99\` only.\n' >> $DOC" "prose says Next.js 99"
t prose_code_span_floor_ascii 1 "printf '\nNext.js \`>=99\` only.\n' >> $DOC" "prose says Next.js 99"
t prose_in_root_agents 1 "printf '\nReact 99 is the floor.\n' >> AGENTS.md" "prose says React 99"
t prose_in_root_readme 1 "printf '\nReact 99 is the floor.\n' >> README.md" "prose says React 99"
# image tokens: any node|python|nginx* name, any prefix, any case, any digit-led tag
t image_major_only_tag 1 "printf '\n\`\`\`dockerfile\nFROM node:20\n\`\`\`\n' >> $DOC" "node:20 is not an image"
t image_registry_prefix 1 "printf '\n\`\`\`dockerfile\nFROM docker.io/library/python:3.9-slim\n\`\`\`\n' >> $DOC" "python:3.9-slim is not an image"
t image_other_registry 1 "printf '\n\`\`\`dockerfile\nFROM mcr.microsoft.com/python:3.9\n\`\`\`\n' >> $DOC" "python:3.9 is not an image"
t image_upper_case 1 "printf '\n\`\`\`dockerfile\nFROM Node:20-alpine\n\`\`\`\n' >> $DOC" "Node:20-alpine is not an image"
t image_other_nginx_name 1 "printf '\n\`\`\`dockerfile\nFROM nginxinc/nginx-unprivileged:1.27\n\`\`\`\n' >> $DOC" "nginx-unprivileged:1.27 is not an image"
t image_listed_tag_passes 0 "printf '\n\`\`\`dockerfile\nFROM node:26-alpine\nFROM --platform=linux/amd64 node:26-alpine AS b\nFROM node:26-alpine@sha256:0123456789abcdef\nFROM docker.io/library/node:26-alpine\n\`\`\`\n' >> $DOC" "check-versions: ok"
# round 3: a code-span name followed by a plain number, ranges, connectors, line breaks, Node and Python
t prose_code_span_next_plain_number 1 "printf '\nNeeds \`next\` 99 here.\n' >> $DOC" "prose says next 99"
t prose_code_span_react_plain_number 1 "printf '\n\`react\` 99\n' >> $DOC" "prose says react 99"
t prose_code_span_vite_plain_number 1 "printf '\n\`vite\` 99\n' >> $DOC" "prose says vite 99"
t prose_code_span_prettier_plain_number 1 "printf '\n\`prettier\` 99\n' >> $DOC" "prose says prettier 99"
t prose_code_span_vitest_plain_number 1 "printf '\n\`vitest\` 99\n' >> $DOC" "prose says vitest 99"
t prose_range_hyphen 1 "printf '\nNext.js 14-99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_range_en_dash 1 "printf '\nNext.js 15 – 99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_range_or 1 "printf '\nNext.js 15 or 99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_colon_after_code_span 1 "printf '\n\`next\`: 99\n' >> $DOC" "prose says next 99"
t prose_to_connector 1 "printf '\nNext.js to 99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_non_breaking_space 1 "printf '\nNext.js\xc2\xa099 only.\n' >> $DOC" "prose says Next.js 99"
t prose_line_break_between 1 "printf '\nNext.js\n99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_line_break_after_sign 1 "printf '\nNext.js ≥\n99 only.\n' >> $DOC" "prose says Next.js 99"
t prose_node_alias 1 "printf '\nNode 99 only.\n' >> $DOC" "prose says Node 99"
t prose_node_js_alias 1 "printf '\nNode.js 99 only.\n' >> $DOC" "prose says Node.js 99"
t prose_python_alias 1 "printf '\nPython 3.99 only.\n' >> $DOC" "prose says Python 3.99"
t prose_next_sentence_start_passes 0 "printf '\nNext 20 items need review.\n' >> $DOC" "check-versions: ok"
t prose_bare_next_documented_limit 0 "printf '\nNeeds Next 99 here.\n' >> $DOC" "check-versions: ok"
t prose_lowercase_node_passes 0 "printf '\nRun node 2 of the cluster.\n' >> $DOC" "check-versions: ok"
t prose_node_below_pin_passes 0 "printf '\nNode 24 is older; Node 26.1 and Python 3.14.2 pass.\n' >> $DOC" "check-versions: ok"
t prose_list_marker_after_line_break_passes 0 "printf '\nInstall React\n20. Then run it.\n' >> $DOC" "check-versions: ok"
t prose_range_within_pin_passes 0 "printf '\nNext.js 14-15 and \`next\` 15 are fine.\n' >> $DOC" "check-versions: ok"
t versions_extra_field_names_the_line 1 "printf 'npm left-pad ^1 extra\n' >> $V" "versions.txt:"
echo "check-versions.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

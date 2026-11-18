#!/usr/bin/env bash
# scripts/check-versions.test.sh — check-versions.sh passes on a copy of the repo and fails on each planted drift.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
base="$T/base"; mkdir -p "$base/scripts"
cp -R "$REPO/skills" "$base/skills"
[[ -d "$REPO/.github" ]] && cp -R "$REPO/.github" "$base/.github"
cp "$REPO/scripts/deploy-smoke.sh" "$base/scripts/"
t() { # t <name> <want rc> <mutation cmd run inside the copy>
  local w="$T/$1"; cp -R "$base" "$w"
  (cd "$w" && eval "$3") >/dev/null 2>&1
  bash "$REPO/scripts/check-versions.sh" --root "$w" >/dev/null 2>&1; local rc=$?
  if [[ $rc -eq $2 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1 — want rc $2, got $rc"; fi
  rm -rf "$w"
}
NJ=skills/scaffold/nextjs/template/package.json
CI=skills/scaffold/shared/template-ci/github-ts/.github/workflows/ci.yml
t baseline 0 true
t npm_spec_drift 1 "sed -i.bak 's/\"vitest\": \"[^\"]*\"/\"vitest\": \"^1.0.0\"/' $NJ"
t pnpm_drift 1 "sed -i.bak 's/pnpm@[0-9.]*/pnpm@1.0.0/' $NJ"
t types_node_drift 1 "sed -i.bak 's/\"@types\\/node\": \"[^\"]*\"/\"@types\\/node\": \"^1\"/' $NJ"
t unlisted_dependency 1 "sed -i.bak 's/\"vitest\":/\"left-pad\": \"^1.0.0\", \"vitest\":/' $NJ"
t action_sha_drift 1 "perl -pi -e 's/checkout\@[0-9a-f]{40}/checkout\@0000000000000000000000000000000000000000/ and \$done++ if !\$done' $CI"
t action_tag_drift 1 "perl -pi -e 's/# v7\\.0\\.1/# v0.0.1/ and \$done++ if !\$done' $CI"
t tool_variable_drift 1 "sed -i.bak 's/DIFF_COVER_VERSION: \"[^\"]*\"/DIFF_COVER_VERSION: \"0.0.1\"/' $CI"
t node_version_drift 1 "perl -pi -e 's/node-version: \"[0-9]+\"/node-version: \"1\"/ and \$done++ if !\$done' $CI"
t gitleaks_drift 1 "sed -i.bak 's/GITLEAKS_VERSION=\"[^\"]*\"/GITLEAKS_VERSION=\"0.0.1\"/' skills/scaffold/shared/template/.claude/ci-gates.sh"
t pip_requirement_drift 1 "sed -i.bak 's/^pytest>=.*/pytest>=1.0/' skills/scaffold/fastapi/template/requirements-dev.txt"
t pip_spec_in_prose 1 "printf '\nUse pytest==9.0 here.\n' >> skills/add/test/SKILL.md"
t package_pin_in_prose 1 "printf '\nInstall vitest@4.1.8 first.\n' >> skills/add/test/SKILL.md"
echo "check-versions.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

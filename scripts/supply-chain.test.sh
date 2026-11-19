#!/usr/bin/env bash
# scripts/supply-chain.test.sh — tests for the seeded check-supply-chain, check-workflows, check-env-example and
# check-dockerfile scripts: each blocks a bad input and allows a good one, and each passes on the real stack templates.
# Usage: bash scripts/supply-chain.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
SC="$SH/template/scripts"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/sct.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# run <dir> <script> [args]: sets OUT and EC from running one seeded script inside a fixture directory.
run() {
  local d=$1 s=$2
  shift 2
  OUT=$(cd "$d" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS PATH="$NOHL:$PATH" bash "$SC/$s" "$@" 2>&1)
  EC=$?
}

# A PATH folder that shadows hadolint with a failing-free stub so the static rules are tested alone.
NOHL="$T/stubs"
mkdir -p "$NOHL"
printf '#!/bin/sh\nexit 0\n' > "$NOHL/hadolint"
chmod +x "$NOHL/hadolint"

# fixture <name>: a fresh directory seeded from a real stack template; echoes the path.
fixture() {
  local d="$T/$1"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  echo "$d"
}

# ── check-supply-chain.sh ─────────────────────────────────────────────────────

NEXT="$SH/../nextjs/template"
sc_pnpm() {
  D=$(fixture "$1")
  cp "$NEXT/package.json" "$NEXT/pnpm-workspace.yaml" "$D/"
}
sc_pnpm sc-good
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain passes on the seeded pnpm settings ($OUT)"

sc_pnpm sc-age
sed 's/^minimumReleaseAge: .*/minimumReleaseAge: 60/' "$NEXT/pnpm-workspace.yaml" > "$D/pnpm-workspace.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a low release age"
has "minimumReleaseAge" "$OUT" "supply-chain names the release age setting"

sc_pnpm sc-noage
grep -v '^minimumReleaseAge' "$NEXT/pnpm-workspace.yaml" > "$D/pnpm-workspace.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a missing release age"

sc_pnpm sc-excl
printf 'minimumReleaseAgeExclude:\n  - left-pad\n' >> "$D/pnpm-workspace.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks minimumReleaseAgeExclude"
has "minimumReleaseAgeExclude" "$OUT" "supply-chain names the exclude setting"

sc_pnpm sc-builds
printf 'dangerouslyAllowAllBuilds: true\n' >> "$D/pnpm-workspace.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks dangerouslyAllowAllBuilds"

sc_pnpm sc-npmrc
printf 'ignore-scripts=false\n' > "$D/.npmrc"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks an .npmrc that re-enables install scripts"

sc_pnpm sc-frozen
mkdir -p "$D/.github/workflows"
printf 'jobs:\n  a:\n    steps:\n      - run: pnpm install\n' > "$D/.github/workflows/ci.yml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a CI pnpm install that is not frozen"
has "--frozen-lockfile" "$OUT" "supply-chain says to add --frozen-lockfile"
printf 'jobs:\n  a:\n    steps:\n      - run: pnpm install --frozen-lockfile\n' > "$D/.github/workflows/ci.yml"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain allows a frozen CI pnpm install ($OUT)"

sc_pnpm sc-host
printf "packages:\n  left-pad@1.0.0:\n    resolution: {tarball: https://evil.example.com/left-pad.tgz}\n" > "$D/pnpm-lock.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a lockfile host outside the default registry"
has "evil.example.com" "$OUT" "supply-chain names the foreign host"
printf 'evil.example.com\n' > "$D/.claude/registry-hosts.txt"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain allows a host listed in registry-hosts.txt ($OUT)"
printf "packages:\n  left-pad@1.0.0:\n    resolution: {tarball: https://registry.npmjs.org/left-pad/-/left-pad-1.0.0.tgz}\n" > "$D/pnpm-lock.yaml"
rm -f "$D/.claude/registry-hosts.txt"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain allows the default registry ($OUT)"

D=$(fixture sc-py)
printf 'fastapi==0.1.0 \\\n    --hash=sha256:%s\n' "$(printf 'a%.0s' {1..64})" > "$D/requirements.txt"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain allows a hashed requirements.txt ($OUT)"
printf 'fastapi==0.1.0\n' > "$D/requirements.txt"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a requirements.txt entry without hashes"
printf 'fastapi>=0.1\n' > "$D/requirements.txt"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks an unpinned requirements.txt entry"
printf 'fastapi==0.1.0 \\\n    --hash=sha256:%s\n' "$(printf 'a%.0s' {1..64})" > "$D/requirements.txt"
mkdir -p "$D/.github/workflows"
printf 'jobs:\n  a:\n    steps:\n      - run: pip install -r requirements.txt\n' > "$D/.github/workflows/ci.yml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a CI pip install without --require-hashes"
printf 'jobs:\n  a:\n    steps:\n      - run: pip install --require-hashes -r requirements.txt\n' > "$D/.github/workflows/ci.yml"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain allows a CI pip install with --require-hashes ($OUT)"

D=$(fixture sc-dep)
mkdir -p "$D/.github"
cp "$SH/template-ci/github-ts/.github/dependabot.yml" "$D/.github/dependabot.yml"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain allows dependabot with a cooldown on every entry ($OUT)"
grep -v 'cooldown' "$SH/template-ci/github-ts/.github/dependabot.yml" > "$D/.github/dependabot.yml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks dependabot entries without a cooldown"
has "cooldown" "$OUT" "supply-chain names the cooldown"

# ── check-workflows.sh ────────────────────────────────────────────────────────

SHA=$(printf 'b%.0s' {1..40})
wf() { # wf <name> <body>: a fixture with one workflow file
  D=$(fixture "$1")
  mkdir -p "$D/.github/workflows"
  printf '%s\n' "$2" > "$D/.github/workflows/ci.yml"
}
GOOD="name: ci
on: [pull_request]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA # v1
        with:
          persist-credentials: false
      - run: echo hi"
wf wf-good "$GOOD"
run "$D" check-workflows.sh
check 0 "$EC" "workflows passes a hardened workflow ($OUT)"
wf wf-tag "${GOOD//@$SHA # v1/@v4}"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks an action pinned to a tag"
has "40-character" "$OUT" "workflows says to pin a SHA"
wf wf-prt "${GOOD//\[pull_request\]/[pull_request_target]}"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks pull_request_target"
wf wf-noperm "${GOOD//permissions:
  contents: read
/}"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks a missing permissions block"
wf wf-write "${GOOD//contents: read/contents: write}"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks write permissions at the top level"
wf wf-inject "$GOOD
      - run: echo \${{ github.event.pull_request.title }}"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks event data inside a run script"
has "env:" "$OUT" "workflows says to pass event data through env"
wf wf-env "$GOOD
      - run: echo \"\$TITLE\"
        env:
          TITLE: \${{ github.event.pull_request.title }}"
run "$D" check-workflows.sh
check 0 "$EC" "workflows allows event data passed through env ($OUT)"
wf wf-persist "${GOOD//        with:
          persist-credentials: false
/}"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks a checkout that persists credentials"
wf wf-push "${GOOD//        with:
          persist-credentials: false
/}
      - run: git push"
run "$D" check-workflows.sh
check 0 "$EC" "workflows allows persisted credentials in a job that pushes ($OUT)"

az() { # az <name> <body>
  D=$(fixture "$1")
  printf '%s\n' "$2" > "$D/azure-pipelines.yml"
}
az az-good "steps:
  - checkout: self
    persistCredentials: false
  - script: echo hi"
run "$D" check-workflows.sh
check 0 "$EC" "workflows passes a hardened Azure pipeline ($OUT)"
az az-persist "steps:
  - checkout: self
    persistCredentials: true
  - script: echo hi"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks Azure persistCredentials: true"
az az-inject "steps:
  - script: echo \$(Build.SourceBranchName)"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks a branch name expanded in an Azure script"
az az-env "steps:
  - script: echo \"\$BRANCH\"
    env:
      BRANCH: \$(Build.SourceBranchName)"
run "$D" check-workflows.sh
check 0 "$EC" "workflows allows a branch name mapped through env ($OUT)"

# ── check-env-example.sh ──────────────────────────────────────────────────────

ee() { # ee <name> <example body> <source body>
  D=$(fixture "$1")
  mkdir -p "$D/src"
  printf '%s\n' "$2" > "$D/.env.example"
  printf '%s\n' "$3" > "$D/src/a.ts"
}
ee ee-good "API_URL=
# OPTIONAL_KEY=" "const a = process.env.API_URL; const b = process.env.OPTIONAL_KEY;"
run "$D" check-env-example.sh
check 0 "$EC" "env-example passes when the code and the example agree ($OUT)"
ee ee-missing "API_URL=" "const a = process.env.API_URL; const b = process.env.NEW_ONE;"
run "$D" check-env-example.sh
check 1 "$EC" "env-example blocks a variable the code reads that the example lacks"
has "NEW_ONE" "$OUT" "env-example names the missing variable"
ee ee-extra "API_URL=
STALE=" "const a = process.env.API_URL;"
run "$D" check-env-example.sh
check 1 "$EC" "env-example blocks an example key no code reads"
has "STALE" "$OUT" "env-example names the stale key"
ee ee-builtin "API_URL=" "const a = process.env.API_URL; const b = process.env.NODE_ENV;"
run "$D" check-env-example.sh
check 0 "$EC" "env-example ignores runtime-set names ($OUT)"
ee ee-real "API_URL=" "const a = process.env.API_URL;"
printf 'SECRET_ONLY_HERE=1\n' > "$D/.env"
run "$D" check-env-example.sh
check 0 "$EC" "env-example never reads a real .env ($OUT)"
D=$(fixture ee-none)
run "$D" check-env-example.sh
check 1 "$EC" "env-example blocks a missing .env.example"

# ── check-dockerfile.sh ───────────────────────────────────────────────────────

DIG=$(printf 'c%.0s' {1..64})
df() { # df <name> <body>
  D=$(fixture "$1")
  printf '%s\n' "$2" > "$D/Dockerfile"
}
GOODDF="FROM node:26-alpine@sha256:$DIG AS build
RUN echo build
FROM node:26-alpine@sha256:$DIG
USER 1000
CMD [\"node\"]"
df df-good "$GOODDF"
run "$D" check-dockerfile.sh
check 0 "$EC" "dockerfile passes a pinned non-root image ($OUT)"
df df-nodigest "${GOODDF//@sha256:$DIG/}"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks an image with no digest"
has "pinned by digest" "$OUT" "dockerfile says to pin a digest"
df df-latest "FROM node:latest@sha256:$DIG
USER 1000"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks :latest"
df df-root "${GOODDF//USER 1000/USER root}"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks USER root"
df df-nouser "${GOODDF//USER 1000/}"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks a final stage with no USER"
df df-add "${GOODDF//CMD/ADD https://example.com/x.tgz /x
CMD}"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks ADD from a URL"
df df-arg "ARG BASE=node:26-alpine@sha256:$DIG
FROM \${BASE}
USER 1000"
run "$D" check-dockerfile.sh
check 0 "$EC" "dockerfile resolves an ARG default that carries the digest ($OUT)"
df df-arg-bad "ARG BASE=node:26-alpine
FROM \${BASE}
USER 1000"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks an ARG default with no digest"
D=$(fixture df-none)
run "$D" check-dockerfile.sh
check 0 "$EC" "dockerfile passes when no Dockerfile exists ($OUT)"

# hadolint absent: a local run warns and passes, a CI run fails.
df df-nohl "$GOODDF"
NOHL_PATH="/usr/bin:/bin"
OUT=$(cd "$D" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS PATH="$NOHL_PATH" /bin/bash "$SC/check-dockerfile.sh" 2>&1)
check 0 "$?" "dockerfile without hadolint passes locally ($OUT)"
has "WARNING" "$OUT" "dockerfile warns loudly when hadolint is missing"
has "brew install hadolint" "$OUT" "dockerfile names the install command"
OUT=$(cd "$D" && env CI=true PATH="$NOHL_PATH" /bin/bash "$SC/check-dockerfile.sh" 2>&1)
check 1 "$?" "dockerfile without hadolint fails in CI"
OUT=$(cd "$D" && env -u CI TF_BUILD=True PATH="$NOHL_PATH" /bin/bash "$SC/check-dockerfile.sh" 2>&1)
check 1 "$?" "dockerfile without hadolint fails on Azure"

# ── the real stack templates ──────────────────────────────────────────────────

for stack in nextjs nestjs vite-react fastapi; do
  TD="$SH/../$stack/template"
  [[ -f "$TD/Dockerfile" ]] || continue
  OUT=$(cd "$TD" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS PATH="$NOHL:$PATH" bash "$SC/check-dockerfile.sh" 2>&1)
  check 0 "$?" "dockerfile passes on the $stack template ($OUT)"
  if [[ -f "$TD/pnpm-workspace.yaml" ]]; then
    OUT=$(cd "$TD" && bash "$SC/check-supply-chain.sh" 2>&1)
    check 0 "$?" "supply-chain passes on the $stack template ($OUT)"
  fi
done

for ci in github-ts github-py; do
  W="$SH/template-ci/$ci/.github/workflows/ci.yml"
  OUT=$(bash "$SC/check-workflows.sh" "$W" 2>&1)
  check 0 "$?" "workflows passes on the $ci template ($OUT)"
done
for f in "$SH/template-ci/azure/azure-pipelines/templatecentral-gates.yml" "$SH/template-ci/azure-ts/azure-pipelines.yml" "$SH/template-ci/azure-py/azure-pipelines.yml"; do
  OUT=$(bash "$SC/check-workflows.sh" "$f" 2>&1)
  check 0 "$?" "workflows passes on $(basename "$(dirname "$f")")/$(basename "$f") ($OUT)"
done

echo "supply-chain.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

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
for q in '"30"' "'30'" '30'; do
  sed "s/default-days: [0-9]*/default-days: $q/" "$SH/template-ci/github-ts/.github/dependabot.yml" > "$D/.github/dependabot.yml"
  run "$D" check-supply-chain.sh
  check 0 "$EC" "supply-chain accepts cooldown default-days: $q ($OUT)"
done
sed 's/default-days: [0-9]*/default-days: "3"/' "$SH/template-ci/github-ts/.github/dependabot.yml" > "$D/.github/dependabot.yml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a quoted cooldown below the floor"
has "below the floor" "$OUT" "supply-chain reports the quoted cooldown value, not no cooldown"

sc_pnpm sc-scp
printf "packages:\n  a@1.0.0:\n    resolution: {repo: git@Evil.Example.com:u/r.git}\n" > "$D/pnpm-lock.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks an scp-style git host"
has "pnpm-lock.yaml:3" "$OUT" "supply-chain reports the line of a mixed-case host"
has "evil.example.com" "$OUT" "supply-chain names the scp host"

sc_pnpm sc-cmds
mkdir -p "$D/.github/workflows"
cmd_case() { # cmd_case <0|1> <command>
  printf 'jobs:\n  a:\n    steps:\n      - run: %s\n' "$2" > "$D/.github/workflows/ci.yml"
  run "$D" check-supply-chain.sh
  check "$1" "$EC" "supply-chain install command [$2] ($OUT)"
}
for c in 'pnpm --dir x install' 'pnpm -C web i' 'pnpm install --frozen-lockfile=false' 'pnpm install --no-frozen-lockfile' 'uv sync --frozen=false' 'pip install -r ./requirements.txt' 'pip install --requirement requirements.txt' 'pip install -rrequirements.txt' 'pnpm install && pnpm install --frozen-lockfile' 'uv pip install -r requirements.txt' 'python -m pip install -r requirements.txt'; do
  cmd_case 1 "$c"
done
for c in 'pnpm --dir x install --frozen-lockfile' 'pnpm install --frozen-lockfile=true' 'pip install --require-hashes -r ./requirements.txt' 'pip install --require-hashes --requirement requirements.txt' 'pip install -r requirements-dev.txt' 'uv sync --locked' 'uv pip install --require-hashes -r requirements.txt' 'npm ci' 'pnpm add -g foo' 'pnpm install --frozen-lockfile && pip install --require-hashes -r requirements.txt'; do
  cmd_case 0 "$c"
done

for form in 'strictDepBuilds: False' 'strictDepBuilds: FALSE' "strictDepBuilds: 'false'" '"minimumReleaseAgeExclude":' '"dangerouslyAllowAllBuilds": TRUE' '"ignoreScripts": false'; do
  sc_pnpm sc-yaml
  printf '%s\n' "$form" >> "$D/pnpm-workspace.yaml"
  run "$D" check-supply-chain.sh
  check 1 "$EC" "supply-chain blocks the YAML form [$form]"
done
sc_pnpm sc-crlf
sed 's/$/\r/' "$NEXT/pnpm-workspace.yaml" > "$D/pnpm-workspace.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain rejects a CRLF pnpm-workspace.yaml"
has "CRLF" "$OUT" "supply-chain says the file is CRLF"
D=$(fixture sc-subdir)
mkdir -p "$D/web"
printf '{}\n' > "$D/web/package.json"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain passes a root with only a subdirectory frontend ($OUT)"
has "web/package.json" "$OUT" "supply-chain prints that a subdirectory frontend is not checked"
D=$(fixture sc-nopy)
run "$D" check-supply-chain.sh
has "no requirements.txt" "$OUT" "supply-chain prints why the hashed-install check did not run"

D=$(fixture sc-cool)
mkdir -p "$D/.github"
for days in 0 3; do
  sed "s/default-days: [0-9]*/default-days: $days/" "$SH/template-ci/github-ts/.github/dependabot.yml" > "$D/.github/dependabot.yml"
  run "$D" check-supply-chain.sh
  check 1 "$EC" "supply-chain blocks a dependabot cooldown of $days days"
  has "default-days" "$OUT" "supply-chain names default-days"
done
sed "s/default-days: [0-9]*/default-days: 14/" "$SH/template-ci/github-ts/.github/dependabot.yml" > "$D/.github/dependabot.yml"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain allows a longer dependabot cooldown ($OUT)"

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

wf wf-jobwa "$GOOD
  b:
    runs-on: ubuntu-latest
    permissions: write-all
    steps:
      - run: echo hi"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks job-level permissions: write-all"
has "write-all" "$OUT" "workflows names write-all"
for ctx in 'inputs.name' 'github.ref_name' 'github.head_ref' 'github.actor' 'steps.x.outputs.y'; do
  wf wf-ctx "$GOOD
      - run: echo \${{ $ctx }}"
  run "$D" check-workflows.sh
  check 1 "$EC" "workflows blocks \${{ $ctx }} inside run"
done
wf wf-gs "$GOOD
      - uses: actions/github-script@$SHA # v7
        with:
          script: |
            const t = '\${{ github.event.issue.title }}'"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks event data inside a github-script script"
wf wf-gs1 "$GOOD
      - uses: actions/github-script@$SHA # v7
        with:
          script: core.info('\${{ github.head_ref }}')"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks event data in a one-line github-script"
wf wf-gsok "$GOOD
      - uses: actions/github-script@$SHA # v7
        with:
          script: |
            core.info(process.env.TITLE)
        env:
          TITLE: \${{ github.event.issue.title }}"
run "$D" check-workflows.sh
check 0 "$EC" "workflows allows github-script that reads event data from env ($OUT)"
wf wf-quoted "${GOOD//        with:
          persist-credentials: false
/}"
sed -i.bak "s|uses: actions/checkout@|uses: \"actions/checkout@|; s|checkout@$SHA # v1|checkout@$SHA\" # v1|" "$D/.github/workflows/ci.yml"
rm -f "$D/.github/workflows/ci.yml.bak"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks a quoted checkout that persists credentials ($OUT)"
D=$(fixture wf-nofile)
run "$D" check-workflows.sh .github/workflows/none.yml
check 1 "$EC" "workflows rejects an argument that is not a file"
has "not a regular file" "$OUT" "workflows says the argument is not a file"
mkdir -p "$D/adir"
run "$D" check-workflows.sh adir
check 1 "$EC" "workflows rejects a directory argument"

az az-push-step "jobs:
  - job: a
    steps:
      - checkout: self
        persistCredentials: true
      - script: git push origin HEAD
  - job: b
    steps:
      - checkout: self
        persistCredentials: true
      - script: echo hi"
run "$D" check-workflows.sh
check 1 "$EC" "workflows keeps the Azure persistCredentials exemption to the job that pushes"
az az-push-ok "jobs:
  - job: a
    steps:
      - checkout: self
        persistCredentials: true
      - script: git push origin HEAD"
run "$D" check-workflows.sh
check 0 "$EC" "workflows allows persistCredentials in the job that pushes ($OUT)"
az az-push-before "jobs:
  - job: a
    steps:
      - script: git push origin HEAD
      - checkout: self
        persistCredentials: true"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks persistCredentials when the push comes before the checkout"
az az-inline "steps:
  - task: AzureCLI@2
    inputs:
      inlineScript: echo \$(Build.SourceBranch)"
run "$D" check-workflows.sh
check 1 "$EC" "workflows blocks a branch macro in an inlineScript"

# A GitHub workflow is judged by its content when its path is not under .github/workflows.
D=$(fixture wf-nopath)
printf 'on: [push]\npermissions: write-all\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > "$D/build.yml"
OUT=$(cd "$D" && bash "$SC/check-workflows.sh" build.yml 2>&1)
check 1 "$?" "workflows applies the GitHub rules to a workflow passed by a path outside .github/workflows ($OUT)"
has "write-all" "$OUT" "workflows reports write-all for a workflow outside .github/workflows"
D=$(fixture wf-composite)
mkdir -p "$D/.github/actions/x"
cat > "$D/.github/actions/x/action.yml" <<'EOF'
name: x
runs:
  using: composite
  steps:
    - run: echo "${{ github.event.issue.title }}"
      shell: bash
EOF
run "$D" check-workflows.sh
check 1 "$EC" "workflows checks composite actions by default ($OUT)"
has "action.yml" "$OUT" "workflows names the composite action file"
printf 'name: x\nruns:\n  using: composite\n  steps:\n    - run: echo hi\n      shell: bash\n' > "$D/.github/actions/x/action.yml"
run "$D" check-workflows.sh
check 0 "$EC" "workflows passes a clean composite action without a permissions block ($OUT)"

# A plain multi-line scalar after run: is still a script.
HEAD="${GOOD%      - run: echo hi}"
wfs() { # wfs <name> <steps>: the hardened header plus extra steps; @SHA@ becomes a pinned SHA
  local steps=${2//@SHA@/$SHA}
  wf "$1" "$HEAD$steps"
}
S_PLAIN=$(cat <<'EOF'
      - run: echo hi
          echo "${{ github.event.pull_request.title }}"
EOF
)
wfs wf-plain "$S_PLAIN"
run "$D" check-workflows.sh
check 1 "$EC" "workflows scans the continuation lines of a plain multi-line run value ($OUT)"
S_PLAIN_ENV=$(cat <<'EOF'
      - run: echo hi
        env:
          T: ${{ github.event.pull_request.title }}
EOF
)
wfs wf-plain-env "$S_PLAIN_ENV"
run "$D" check-workflows.sh
check 0 "$EC" "workflows allows event data under env: after a plain run value ($OUT)"
# github-script: the script key decides nothing by line order within the step.
S_GS_BEFORE=$(cat <<'EOF'
      - name: s
        with:
          script: |
            core.info("${{ github.event.pull_request.title }}")
        uses: actions/github-script@@SHA@ # v7
EOF
)
wfs wf-gs-before "$S_GS_BEFORE"
run "$D" check-workflows.sh
check 1 "$EC" "workflows scans github-script when script: comes before uses: ($OUT)"
S_GS_AFTER=$(cat <<'EOF'
      - uses: actions/github-script@@SHA@ # v7
        with:
          script: |
            core.info("${{ github.event.pull_request.title }}")
EOF
)
wfs wf-gs-after "$S_GS_AFTER"
run "$D" check-workflows.sh
check 1 "$EC" "workflows scans github-script when uses: comes first ($OUT)"
S_GS_OK=$(cat <<'EOF'
      - name: s
        with:
          script: |
            core.info("hi")
        uses: actions/github-script@@SHA@ # v7
      - run: echo "${{ github.event.number }}"
EOF
)
wfs wf-gs-ok "$S_GS_OK"
run "$D" check-workflows.sh
check 0 "$EC" "workflows passes a safe github-script step and a plain run after it ($OUT)"

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
ee ee-real "API_URL=" "const a = process.env.API_URL; const b = process.env.SECRET_ONLY_HERE;"
printf 'SECRET_ONLY_HERE=1\n' > "$D/.env"
run "$D" check-env-example.sh
check 1 "$EC" "env-example never reads a real .env: a key only the .env has is still missing ($OUT)"
has "SECRET_ONLY_HERE" "$OUT" "env-example names the key the .env alone had"
ee ee-destr "API_URL=" "const { API_URL, OTHER_ONE: x = 'd' } = process.env;"
run "$D" check-env-example.sh
check 1 "$EC" "env-example reads a destructured process.env"
has "OTHER_ONE" "$OUT" "env-example names the destructured variable"
ee ee-destr-ml "API_URL=" "const {
  API_URL,
  MULTI_LINE,
} = process.env;"
run "$D" check-env-example.sh
check 1 "$EC" "env-example reads a multi-line destructured process.env"
has "MULTI_LINE" "$OUT" "env-example names the multi-line destructured variable"
ee ee-optional "API_URL=" "const a = process.env.API_URL; const b = process.env?.OPT_CHAIN;"
run "$D" check-env-example.sh
check 1 "$EC" "env-example reads optional chaining process.env?.X"
has "OPT_CHAIN" "$OUT" "env-example names the optional-chaining variable"
ee ee-pyspace "API_URL=" "import os
a = os.environ.get( \"API_URL\")
b = os.environ.get( \"PY_SPACED\")"
printf '%s\n' "$(cat "$D/src/a.ts")" > "$D/src/a.py"
rm "$D/src/a.ts"
run "$D" check-env-example.sh
check 1 "$EC" "env-example reads os.environ.get with a space after the paren"
has "PY_SPACED" "$OUT" "env-example names the spaced os.environ.get variable"
ee ee-export "export API_URL=
# export OPT_KEY =" "const a = process.env.API_URL; const b = process.env.OPT_KEY;"
run "$D" check-env-example.sh
check 0 "$EC" "env-example accepts export NAME= and NAME = lines ($OUT)"
ee ee-spaced-eq "API_URL = http://x" "const a = process.env.API_URL;"
run "$D" check-env-example.sh
check 0 "$EC" "env-example accepts NAME = value ($OUT)"
ee ee-scanned "API_URL=" "const a = process.env.API_URL;"
run "$D" check-env-example.sh
has "scanned src" "$OUT" "env-example prints the directories it scanned"
ee ee-outside "API_URL=" "const a = process.env.API_URL;"
mkdir -p "$D/server"
printf 'const x = process.env.SERVER_ONLY;\n' > "$D/server/index.ts"
run "$D" check-env-example.sh
check 0 "$EC" "env-example still passes when source sits outside the scanned directories ($OUT)"
has "source exists outside the scanned directories (server)" "$OUT" "env-example warns about source outside the scanned directories"
ee ee-aux "API_URL=" "const a = process.env.API_URL;"
mkdir -p "$D/test/api" "$D/tests" "$D/docs" "$D/scripts" "$D/.claude/hooks"
for x in test/api tests docs scripts .claude/hooks; do printf 'const y = 1;\n' > "$D/$x/a.ts"; done
run "$D" check-env-example.sh
check 0 "$EC" "env-example passes with test, tests, docs, scripts and .claude directories ($OUT)"
if [[ "$OUT" == *"outside the scanned"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: env-example warns about test, docs or scripts directories: $OUT"; else PASS=$((PASS + 1)); fi
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

df df-user00 "${GOODDF//USER 1000/USER 00}"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks USER 00"
df df-user0000 "${GOODDF//USER 1000/USER 0000:0}"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks USER 0000:0"
df df-addjson "${GOODDF//CMD/ADD [\"https://example.com/x.tgz\", \"/x\"]
CMD}"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks a JSON-form ADD from a URL"
df df-default "FROM \${IMG:-node:20}
USER 1000"
run "$D" check-dockerfile.sh
check 1 "$EC" "dockerfile blocks an ARG default form with no digest"
has "base image node:20 is not pinned" "$OUT" "dockerfile message names the resolved default image"
df df-default-ok "ARG IMG=node:26-alpine@sha256:$DIG
FROM \${IMG:-node:20}
USER 1000"
run "$D" check-dockerfile.sh
check 0 "$EC" "dockerfile uses the ARG value over its :- default ($OUT)"
df df-heredoc "FROM node:26-alpine@sha256:$DIG
RUN <<EOF
echo hello
FROM bogus-image
EOF
USER 1000"
run "$D" check-dockerfile.sh
check 0 "$EC" "dockerfile ignores a FROM inside a RUN heredoc ($OUT)"

# hadolint stubs: a failing stub fails the gate, and the gate strips every way to loosen it.
FAILHL="$T/failhl"
mkdir -p "$FAILHL"
printf '#!/bin/sh\necho "stub finding" >&2\nexit 1\n' > "$FAILHL/hadolint"
chmod +x "$FAILHL/hadolint"
df df-hlfail "$GOODDF"
OUT=$(cd "$D" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS PATH="$FAILHL:$PATH" bash "$SC/check-dockerfile.sh" 2>&1)
check 1 "$?" "dockerfile fails when hadolint reports a finding"
has "Fix them" "$OUT" "dockerfile says to fix hadolint findings"
SPYHL="$T/spyhl"
mkdir -p "$SPYHL"
cat > "$SPYHL/hadolint" <<'STUB'
#!/bin/sh
printf 'ARGS=%s IGN=%s THR=%s\n' "$*" "${HADOLINT_IGNORE:-none}" "${HADOLINT_FAILURE_THRESHOLD:-none}" > "$SPY_OUT"
exit 0
STUB
chmod +x "$SPYHL/hadolint"
df df-hlargs "$GOODDF"
printf 'ignored:\n  - DL3008\n' > "$D/.hadolint.yaml"
OUT=$(cd "$D" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS SPY_OUT="$T/spy.txt" HADOLINT_IGNORE=DL3008 HADOLINT_FAILURE_THRESHOLD=none PATH="$SPYHL:$PATH" bash "$SC/check-dockerfile.sh" 2>&1)
check 0 "$?" "dockerfile runs a clean stub ($OUT)"
SPY=$(cat "$T/spy.txt")
has "--disable-ignore-pragma" "$SPY" "dockerfile turns off inline ignore pragmas"
has "--config" "$SPY" "dockerfile passes its own hadolint config"
has "IGN=none" "$SPY" "dockerfile unsets HADOLINT_IGNORE"
has "THR=none" "$SPY" "dockerfile unsets HADOLINT_FAILURE_THRESHOLD"

# CI=false is not CI.
df df-cifalse "$GOODDF"
OUT=$(cd "$D" && env -u TF_BUILD -u GITHUB_ACTIONS CI=false PATH="/usr/bin:/bin" /bin/bash "$SC/check-dockerfile.sh" 2>&1)
check 0 "$?" "dockerfile treats CI=false as a local run ($OUT)"
OUT=$(cd "$D" && env -u TF_BUILD -u GITHUB_ACTIONS CI=false PATH="/usr/bin:/bin" /bin/bash "$SC/check-secret-scanner.sh" 2>&1)
check 0 "$?" "secret scanner treats CI=false as a local run ($OUT)"
OUT=$(cd "$D" && env -u TF_BUILD -u GITHUB_ACTIONS CI=true PATH="/usr/bin:/bin" /bin/bash "$SC/check-secret-scanner.sh" 2>&1)
check 1 "$?" "secret scanner fails in CI=true"
OUT=$(cd "$D" && env -u CI -u TF_BUILD GITHUB_ACTIONS=true PATH="/usr/bin:/bin" /bin/bash "$SC/check-secret-scanner.sh" 2>&1)
check 1 "$?" "secret scanner fails on GitHub Actions without gitleaks"
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS TF_BUILD=True PATH="/usr/bin:/bin" /bin/bash "$SC/check-secret-scanner.sh" 2>&1)
check 1 "$?" "secret scanner fails on Azure without gitleaks"

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
  if [[ -f "$TD/.env.example" ]]; then
    OUT=$(cd "$TD" && bash "$SC/check-env-example.sh" 2>&1)
    check 0 "$?" "env-example passes on the $stack template ($OUT)"
    if [[ "$OUT" == *"outside the scanned directories"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: env-example warns falsely on the $stack template: $OUT"; else PASS=$((PASS + 1)); fi
  fi
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

# A workspace file over one pipe buffer with the setting on line 1 is still read: the match must not depend on the writer finishing.
sc_pnpm sc-big-excl
{ printf 'minimumReleaseAgeExclude:\n  - left-pad\n'; cat "$NEXT/pnpm-workspace.yaml"; for ((i = 0; i < 4000; i++)); do printf '# padding line number %05d to push the file past sixty-four kilobytes\n' "$i"; done; } > "$D/pnpm-workspace.yaml"
size=$(wc -c < "$D/pnpm-workspace.yaml" | tr -d ' ')
check 1 "$([ "$size" -gt 262144 ] && echo 1 || echo 0)" "big workspace fixture is over 256 KB ($size)"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks minimumReleaseAgeExclude on line 1 of a big file"
has "minimumReleaseAgeExclude" "$OUT" "big file: names the exclude setting"

sc_pnpm sc-big-ok
{ cat "$NEXT/pnpm-workspace.yaml"; for ((i = 0; i < 4000; i++)); do printf '# padding line number %05d to push the file past sixty-four kilobytes\n' "$i"; done; } > "$D/pnpm-workspace.yaml"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain passes a big clean workspace file ($OUT)"

sc_pnpm sc-big-age
{ printf 'minimumReleaseAge: 60\n'; grep -v '^minimumReleaseAge' "$NEXT/pnpm-workspace.yaml"; for ((i = 0; i < 4000; i++)); do printf '# padding line number %05d to push the file past sixty-four kilobytes\n' "$i"; done; } > "$D/pnpm-workspace.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a low release age on line 1 of a big file"

# A lockfile with many hosts: an allow-listed host is found whichever line it is on, and a foreign one is still named.
sc_pnpm sc-big-hosts
{ for ((i = 0; i < 3000; i++)); do printf '  l%05d@1.0.0:\n    resolution: {tarball: https://registry.npmjs.org/l%05d.tgz}\n' "$i" "$i"; done; printf '  x@1.0.0:\n    resolution: {tarball: https://evil.example.com/x.tgz}\n'; } > "$D/pnpm-lock.yaml"
run "$D" check-supply-chain.sh
check 1 "$EC" "supply-chain blocks a foreign host at the end of a big lockfile"
has "evil.example.com" "$OUT" "big lockfile: names the foreign host"
{ for ((i = 0; i < 6000; i++)); do printf 'host%05d.example.net\n' "$i"; done; printf 'evil.example.com\n'; } > "$D/.claude/registry-hosts.txt"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain finds a host at the end of a big allow-list ($OUT)"
{ printf 'evil.example.com\n'; for ((i = 0; i < 6000; i++)); do printf 'host%05d.example.net\n' "$i"; done; } > "$D/.claude/registry-hosts.txt"
run "$D" check-supply-chain.sh
check 0 "$EC" "supply-chain finds a host on line 1 of a big allow-list ($OUT)"

echo "supply-chain.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

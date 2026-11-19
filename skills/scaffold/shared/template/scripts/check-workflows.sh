#!/usr/bin/env bash
# Workflow hardening lint for GitHub workflows and Azure pipelines: pinned actions, least-privilege token,
# no pull_request_target, no untrusted event data in scripts, no persisted checkout credentials. No network.
# Usage: bash scripts/check-workflows.sh [file ...]   (default: every workflow and pipeline file)
set -uo pipefail

bad_count=0
bad() {
  printf '%s\n' "$1" >&2
  bad_count=$((bad_count + 1))
}

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  for f in .github/workflows/*.yml .github/workflows/*.yaml .github/actions/*/action.yml .github/actions/*/action.yaml azure-pipelines.yml azure-pipelines/*.yml; do
    if [ -f "$f" ]; then files+=("$f"); fi
  done
fi

sha_ref='@[0-9a-f]{40}$'
docker_ref='@sha256:[0-9a-f]{64}$'

github_pins() {
  local f=$1 n val
  while IFS= read -r row; do
    n=${row%%:*}
    val=${row#*:}
    val=$(printf '%s' "$val" | sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^["'"'"']//; s/["'"'"']$//')
    case "$val" in ./*) continue ;; esac
    if [[ "$val" == docker://* ]]; then
      if [[ ! "$val" =~ $docker_ref ]]; then bad "$f:$n: image $val is not pinned by digest. Pin it as docker://<image>@sha256:<64 hex>."; fi
    elif [[ ! "$val" =~ $sha_ref ]]; then
      bad "$f:$n: action $val is not pinned to a 40-character commit SHA. Pin it as owner/repo@<sha> # <tag>, then let Dependabot bump it."
    fi
  done < <(grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:' "$f" | grep -vE '^[0-9]+:[[:space:]]*#')
}

# A file gets the GitHub rules by its path or, for a path outside .github, by its content (runs-on or a composite action).
is_github() {
  case "$1" in
    *.github/workflows/* | *.github/actions/*/action.yml | *.github/actions/*/action.yaml) return 0 ;;
  esac
  grep -qE '^[[:space:]]*runs-on:|^[[:space:]]*using:[[:space:]]*["'"'"']?composite' "$1"
}

github_structure() {
  local composite=0
  if grep -qE '^[[:space:]]*using:[[:space:]]*["'"'"']?composite' "$1"; then composite=1; fi
  awk -v file="$1" -v composite="$composite" '
    function indent_of(s,   t) { t = s; sub(/[^ ].*$/, "", t); return length(t) }
    function report(n, msg) { printf "%s:%d: %s\n", file, n, msg; found = 1 }
    function end_job() {
      if (injob && checkouts != persist && !pushes) {
        report(checkout_line, "checkout keeps its credentials in the git config. Add `persist-credentials: false` to the checkout step, or run the push from a job that needs it.")
      }
      checkouts = 0; persist = 0; pushes = 0; injob = 0
    }
    function scan_run(n, text,   t) {
      if (text ~ /git[[:space:]]+push/) pushes = 1
      t = text
      gsub(/[$][{][{][[:space:]]*github[.]event[.]number[[:space:]]*[}][}]/, "", t)
      gsub(/[$][{][{][[:space:]]*github[.]event[.]pull_request[.]number[[:space:]]*[}][}]/, "", t)
      if (t ~ /[$][{][{][^}]*(github[.]event[.]|github[.]head_ref|github[.]ref_name|github[.]actor|inputs[.]|steps[.][A-Za-z0-9_-]+[.]outputs[.])/) {
        report(n, "untrusted data (event, branch name, actor, input or step output) inside a script can inject commands. Pass it through env: (NAME: ${{ github.event... }}) and read \"$NAME\" in the script.")
      }
    }
    BEGIN { curstep = 0; curind = -1; gscript = 0; inrun = 0; in_jobs = 0; injob = 0; toplevel_perm = 0; perm_block = 0; has_perm = 0; checkouts = 0; persist = 0; pushes = 0 }
    # First pass: which lines belong to a step that uses actions/github-script, wherever the script key sits in the step.
    FNR == NR {
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) next
      pind = indent_of($0); ps = $0; sub(/^ +/, "", ps)
      if (ps ~ /^-([[:space:]]|$)/) {
        if (!(curstep && pind > curind)) { curstep = FNR; curind = pind }
      } else if (curstep && pind <= curind) curstep = 0
      if (curstep) {
        stepof[FNR] = curstep
        if (ps ~ /uses:[[:space:]]*["'"'"']?actions\/github-script@/) gsstep[curstep] = 1
      }
      next
    }
    /^[[:space:]]*$/ { next }
    {
      ind = indent_of($0)
      s = $0; sub(/^ +/, "", s)
      if (s ~ /^#/) next
      if (inrun && ind > runcol) { scan_run(FNR, s); next }
      inrun = 0
      if (ind == 0) {
        perm_block = 0
        in_jobs = (s ~ /^jobs:/)
        if (s ~ /^permissions:/) {
          has_perm = 1
          v = s; sub(/^permissions:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
          if (v == "write-all") report(FNR, "top-level permissions: write-all grants every scope. Declare `permissions: { contents: read }` and widen per job.")
          else if (v == "") perm_block = 1
          else if (v ~ /write/) report(FNR, "top-level permissions grant write access. Declare `permissions: { contents: read }` and widen per job.")
        }
        if (s ~ /^(on|"on"|true):/ && s ~ /pull_request_target/) report(FNR, "pull_request_target runs fork code with repository secrets. Use pull_request, or split the privileged step into a separate workflow_run.")
      }
      if (s ~ /pull_request_target/ && s !~ /^permissions:/) report(FNR, "pull_request_target runs fork code with repository secrets. Use pull_request, or split the privileged step into a separate workflow_run.")
      if (perm_block && ind > 0 && s ~ /:[[:space:]]*write([[:space:]]|$)/) report(FNR, "top-level permissions grant write access. Declare `permissions: { contents: read }` and widen per job.")
      if (s ~ /write-all/ && !(ind == 0 && s ~ /^permissions:/)) report(FNR, "permissions: write-all grants every scope. List only the scopes this job needs.")
      if (in_jobs && ind == 2 && s ~ /^[A-Za-z0-9_-]+:[[:space:]]*$/) { end_job(); injob = 1 }
      if (s ~ /uses:[[:space:]]*["'"'"']?actions\/checkout@/) { checkouts++; checkout_line = FNR }
      if (s ~ /persist-credentials:[[:space:]]*["'"'"']?false/) persist++
      gscript = (FNR in stepof) && (stepof[FNR] in gsstep)
      if (gscript && s ~ /^(-[[:space:]]+)?script:/) {
        col = ind + ((s ~ /^-/) ? 2 : 0)
        v = s; sub(/^(-[[:space:]]+)?script:[[:space:]]*/, "", v)
        if (v !~ /^[|>]/) scan_run(FNR, v)
        inrun = 1; runcol = col
      }
      if (s ~ /^(-[[:space:]]+)?run:/) {
        col = ind + ((s ~ /^-/) ? 2 : 0)
        v = s; sub(/^(-[[:space:]]+)?run:[[:space:]]*/, "", v)
        if (v !~ /^[|>]/) scan_run(FNR, v)
        inrun = 1; runcol = col
      }
    }
    END {
      end_job()
      if (!has_perm && !composite) report(1, "no top-level `permissions:` block, so the token takes the repository default. Add `permissions: { contents: read }`.")
      exit found
    }
  ' "$1" "$1"
}

azure_rules() {
  local f=$1 out
  out=$(awk -v file="$f" '
    function flush() { if (pending) { printf "%s:%d: checkout persists the access token in the git config and no later step in the same job pushes. Remove persistCredentials: true, or move the push into a step after the checkout.\n", file, pending; found = 1 } pending = 0 }
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*-[[:space:]]+(job|deployment):/ || /^[[:space:]]*-[[:space:]]+stage:/ || /^[[:space:]]*stages:/ || /^[[:space:]]*jobs:/ { flush() }
    /persistCredentials:[[:space:]]*["'"'"']?[Tt][Rr][Uu][Ee]/ { if (!pending) pending = NR }
    pending && /git[[:space:]]+push/ { pending = 0 }
    END { flush(); exit found }
  ' "$f") || true
  if [ -n "$out" ]; then
    printf '%s\n' "$out" >&2
    bad_count=$((bad_count + 1))
  fi
}

azure_injection() {
  local f=$1 hit
  hit=$(grep -nE '[$][(](Build[.]SourceBranch(Name)?|System[.]PullRequest[.](SourceBranch|SourceBranchName)|Build[.]SourceVersionMessage|Build[.]RequestedFor(Email)?)[)]' "$f" \
    | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vE '^[0-9]+:[[:space:]]*(-[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*:[[:space:]]|[A-Za-z_][A-Za-z0-9_]*:$)' \
    | head -n 1)
  if [ -z "$hit" ]; then
    hit=$(grep -nE '^[[:space:]]*(-[[:space:]]+)?(script|bash|powershell|pwsh|inlineScript):[[:space:]].*[$][(](Build[.]SourceBranch(Name)?|System[.]PullRequest[.](SourceBranch|SourceBranchName)|Build[.]SourceVersionMessage|Build[.]RequestedFor(Email)?)[)]' "$f" | head -n 1)
  fi
  if [ -n "$hit" ]; then bad "$f:${hit%%:*}: a branch name or commit message is expanded inside a script and can inject shell commands. Map it under env: (NAME: \$(Build.SourceBranch)) and read \"\$NAME\"."; fi
}

if [ "${#files[@]}" -eq 0 ]; then
  echo "check-workflows: no workflow or pipeline file found" >&2
  exit 1
fi
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    bad "check-workflows: $f is not a regular file. Pass the path of a workflow or pipeline file, or run with no arguments to check them all."
    continue
  fi
  if is_github "$f"; then
    github_pins "$f"
    out=$(github_structure "$f") || true
    if [ -n "$out" ]; then printf '%s\n' "$out" >&2; bad_count=$((bad_count + 1)); fi
  else
    azure_rules "$f"
    azure_injection "$f"
  fi
done

if [ "$bad_count" -ne 0 ]; then exit 1; fi
echo "check-workflows: ok (${#files[@]} files)"

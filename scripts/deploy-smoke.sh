#!/usr/bin/env bash
# scripts/deploy-smoke.sh — scaffold one stack into a scratch dir, then prove it builds and runs as deployed.
#
# Usage: bash scripts/deploy-smoke.sh <nextjs|vite-react|fastapi|nestjs> [--no-docker] [--keep]
#   Scaffolds with the same tc-copy.sh parts the scaffold skills run, installs dependencies, runs the
#   stack's own build / lint / typecheck / test, builds the template Dockerfile, runs the container and
#   checks it answers HTTP (/health for the APIs, / for the frontends), then runs .claude/verify-harness.sh.
#   Prints a PASS/FAIL/SKIP row per step with the first failing line; exit 1 on any FAIL.
#   --no-docker  skip the two Docker steps (also what happens when no Docker daemon answers)
#   DEPLOY_SMOKE_CA_FILE=<pem>  for a network that re-signs TLS: the CA is passed to the build as a BuildKit secret
#                and appended to the image trust store before each `RUN apk`, in the scratch Dockerfile only
#   --keep       leave the scratch dir (printed at the end) instead of removing it
# Needs network (package registries, shadcn registry, Docker base images), git, node, pnpm (TS stacks),
# python3.14 (fastapi), docker. Run it outside a sandbox.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPY="$REPO_ROOT/skills/scaffold/shared/tc-copy.sh"
STACK="" DOCKER=1 KEEP=0
for a in "$@"; do
  case "$a" in
    --no-docker) DOCKER=0 ;;
    --keep) KEEP=1 ;;
    -h | --help) sed -n 2,12p "${BASH_SOURCE[0]}"; exit 0 ;;
    nextjs | vite-react | fastapi | nestjs) STACK="$a" ;;
    *) echo "deploy-smoke: unknown argument $a" >&2; exit 2 ;;
  esac
done
[[ -n "$STACK" ]] || { echo "usage: deploy-smoke.sh <nextjs|vite-react|fastapi|nestjs> [--no-docker] [--keep]" >&2; exit 2; }

W=$(mktemp -d) || exit 2
P="$W/proj"
LOGS="$W/logs"
mkdir -p "$P" "$LOGS"
NAME="tcsmoke-$STACK"
IMG="$NAME:smoke"
CID=""
# shellcheck disable=SC2317,SC2329
cleanup() {
  [[ -n "$CID" ]] && docker rm -f "$CID" > /dev/null 2>&1
  docker image rm -f "$IMG" > /dev/null 2>&1
  if [[ $KEEP -eq 1 ]]; then echo "kept: $W"; else rm -rf "$W"; fi
}
trap cleanup EXIT

declare -a ROWS=()
FAILED=0
row() { ROWS+=("$(printf '%-18s %-5s %s' "$1" "$2" "${3:-}")"); [[ "$2" == FAIL ]] && FAILED=1; }
# first line of a log that looks like an error, else its last non-empty line
failing_line() {
  local l
  l=$(grep -m1 -iE 'error|fail|not found|cannot|denied|refus' "$1" 2> /dev/null | cut -c1-200)
  [[ -n "$l" ]] || l=$(grep -v '^[[:space:]]*$' "$1" 2> /dev/null | tail -n 1 | cut -c1-200)
  printf '%s' "$l"
}
# step <label> <command...> — run in the project; true when it passes
step() {
  local label="$1"; shift
  local log="$LOGS/${label// /_}.log"
  echo ">> $label: $*" >&2
  if (cd "$P" && "$@") > "$log" 2>&1; then row "$label" PASS; return 0; fi
  row "$label" FAIL "$(failing_line "$log")"
  return 1
}
skip() { row "$1" SKIP "$2"; }
part() { TC_STACK="$STACK" TC_PART="$1" TC_CI="${2:-}" bash "$COPY" "$P" > "$LOGS/part-$1.log" 2>&1 || { echo "scaffold part $1 failed:" >&2; cat "$LOGS/part-$1.log" >&2; exit 1; }; }

# ── scaffold (the tc-copy.sh parts the scaffold skills run, in their order) ──
TITLE="Smoke $STACK"
part stack
part base
(cd "$P" && git init -q && git config user.email smoke@example.com && git config user.name smoke)
case "$STACK" in
  nextjs | vite-react | nestjs) PKG="$P/package.json"; sed -i.bak "s/__TC_PROJECT_NAME__/$NAME/g" "$PKG" && rm -f "$PKG.bak" ;;
esac
[[ -f "$P/src/.env.default" ]] && cp "$P/src/.env.default" "$P/src/.env"
[[ -f "$P/.env.example" && "$STACK" == nextjs ]] && cp "$P/.env.example" "$P/.env.local"

# ── install ──
case "$STACK" in
  fastapi)
    step install bash -c '
      set -e
      python3.14 -m venv .venv && . .venv/bin/activate
      pip install "fastapi>=0.136" "uvicorn[standard]" "pydantic>=2.12" pydantic-settings python-dotenv "python-multipart>=0.0.31" "structlog>=25.1" "starlette>=1.3.1" "certifi>=2026.10.19"
      pip freeze > requirements.txt
      pip install -r requirements-dev.txt
      pip check' ;;
  *)
    step install pnpm install || true ;;
esac
INSTALLED=$([[ "${ROWS[0]}" == *PASS* ]] && echo 1 || echo 0)
if [[ "$STACK" == nextjs || "$STACK" == vite-react ]] && [[ $INSTALLED -eq 1 ]]; then
  if [[ "$STACK" == nextjs ]]; then UI="button card dialog field form input label select separator sonner tabs textarea"
  else UI="accordion avatar button button-group card checkbox dialog dropdown-menu field form input input-group label select separator skeleton sonner tabs textarea"; fi
  # shellcheck disable=SC2086
  step "shadcn add" npx --yes shadcn@latest add $UI || INSTALLED=0
fi

# ── build / lint / typecheck / test ──
if [[ $INSTALLED -eq 1 ]]; then
  case "$STACK" in
    fastapi)
      V=". .venv/bin/activate"
      bash -c "cd '$P' && $V && ruff format src/" > "$LOGS/format.log" 2>&1
      step build bash -c "$V && python -c 'import sys; sys.path.insert(0, \"src\"); import app'" || true
      step lint bash -c "$V && ruff check src/ && ruff format --check src/" || true
      step typecheck bash -c "$V && python -m pyright src/" || true
      step test bash -c "$V && python -m pytest test/ -v" || true ;;
    *)
      (cd "$P" && pnpm format) > "$LOGS/format.log" 2>&1
      step build pnpm build || true
      if [[ "$STACK" == nestjs ]]; then step lint pnpm exec eslint "{src,test}/**/*.ts" || true; else step lint pnpm exec eslint . || true; fi
      step typecheck pnpm exec tsc --noEmit || true
      step test pnpm test || true
      [[ "$STACK" == nestjs ]] && { step "test e2e" pnpm test:e2e || true; } ;;
  esac
else
  for s in build lint typecheck test; do skip "$s" "install failed"; done
fi

# ── harness: the rest of the scaffold parts, then verify-harness ──
part agents
if [[ -f "$P/AGENTS.md" ]]; then sed -i.bak "s/__TC_PROJECT_TITLE__/$TITLE/g" "$P/AGENTS.md" && rm -f "$P/AGENTS.md.bak"; fi
part settings
part late
if [[ -f "$P/docs/CONSTITUTION.md" ]]; then sed -i.bak "s/__TC_PROJECT_TITLE__/$TITLE/g" "$P/docs/CONSTITUTION.md" && rm -f "$P/docs/CONSTITUTION.md.bak"; fi
part ci github
part manifest

# ── docker ──
if [[ $DOCKER -eq 1 ]] && ! docker info > /dev/null 2>&1; then
  echo "deploy-smoke: no Docker daemon answers; skipping the Docker steps" >&2
  DOCKER=0
fi
if [[ $DOCKER -eq 1 ]]; then
  PORT_IN=3000 PATH_OK=/
  case "$STACK" in
    fastapi) PORT_IN=8000 PATH_OK=/health ;;
    nestjs) PATH_OK=/health ;;
    nextjs) PATH_OK=/api/health ;;
  esac
  BUILD_ARGS=()
  if [[ -n "${DEPLOY_SMOKE_CA_FILE:-}" ]]; then
    # Every `RUN apk` gets the CA first: appended to the bundle (needed before ca-certificates is installed) and
    # copied where update-ca-certificates re-reads it (so the trigger from `apk add ca-certificates` keeps it).
    # A later `&& apk upgrade` continuation line in the same RUN re-appends it as a fallback.
    ca=/run/secrets/ca
    setup="mkdir -p /usr/local/share/ca-certificates \&\& cp $ca /usr/local/share/ca-certificates/smoke-ca.crt \&\& cat $ca >> /etc/ssl/certs/ca-certificates.crt \&\& "
    sed -i.bak -E \
      -e "s#^RUN apk#RUN --mount=type=secret,id=ca ${setup}apk#" \
      -e "/^RUN /!s#&& apk upgrade#\&\& cat $ca >> /etc/ssl/certs/ca-certificates.crt \&\& apk upgrade#" \
      "$P/Dockerfile" && rm -f "$P/Dockerfile.bak"
    BUILD_ARGS=(--secret "id=ca,src=$DEPLOY_SMOKE_CA_FILE")
  fi
  if step "docker build" docker build ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} -t "$IMG" .; then
    HP=$((20000 + RANDOM % 20000))
    # a non-http-proxy stack needs no env; the APIs read src/.env or the defaults baked into the image
    CID=$(docker run -d -p "$HP:$PORT_IN" "$IMG" 2> "$LOGS/run.log")
    if [[ -z "$CID" ]]; then
      row "container http" FAIL "$(failing_line "$LOGS/run.log")"
    else
      code=000
      for _ in $(seq 1 30); do
        code=$(curl -s -o "$LOGS/http.body" -w '%{http_code}' "http://127.0.0.1:$HP$PATH_OK" 2> /dev/null)
        [[ "$code" == 200 ]] && break
        [[ "$(docker inspect -f '{{.State.Running}}' "$CID" 2> /dev/null)" == true ]] || break
        sleep 1
      done
      if [[ "$code" == 200 ]]; then
        row "container http" PASS "GET $PATH_OK -> 200"
      else
        docker logs "$CID" > "$LOGS/container.log" 2>&1
        row "container http" FAIL "GET $PATH_OK -> $code; $(failing_line "$LOGS/container.log")"
      fi
      docker rm -f "$CID" > /dev/null 2>&1
      CID=""
    fi
  else
    skip "container http" "docker build failed"
  fi
else
  skip "docker build" "docker unavailable or --no-docker"
  skip "container http" "docker unavailable or --no-docker"
fi

step verify-harness bash .claude/verify-harness.sh || true

echo
echo "== $STACK =="
printf '%s\n' "${ROWS[@]}"
if [[ $FAILED -ne 0 ]]; then
  echo "logs: $W/logs (rerun with --keep to retain)"
  exit 1
fi
exit 0

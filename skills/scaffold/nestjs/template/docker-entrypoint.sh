#!/bin/sh

MODE="${1:-prod}"

# Detect package manager
if [ -f "yarn.lock" ]; then
  PM="yarn"
elif [ -f "pnpm-lock.yaml" ]; then
  corepack enable pnpm
  PM="pnpm"
else
  PM="npm"
fi

case "$MODE" in
  dev)
    exec $PM run start:dev
    ;;
  start|prod)
    exec node dist/main.js
    ;;
  *)
    exec "$@"
    ;;
esac

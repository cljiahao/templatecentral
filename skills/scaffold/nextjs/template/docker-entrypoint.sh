#!/bin/sh

if [ -f "yarn.lock" ]; then
  exec yarn "$@"
elif [ -f "pnpm-lock.yaml" ]; then
  exec sh -c 'corepack enable pnpm && exec pnpm "$@"' -- "$@"
else
  exec npm "$@"
fi

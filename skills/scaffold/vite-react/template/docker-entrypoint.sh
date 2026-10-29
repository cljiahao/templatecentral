#!/bin/sh

if [ -f "yarn.lock" ]; then
  exec yarn "$@"
elif [ -f "pnpm-lock.yaml" ]; then
  exec sh -c 'corepack enable pnpm && exec pnpm "$@"' sh "$@"
else
  exec npm "$@"
fi

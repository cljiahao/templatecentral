#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984: the cached connect promise is reset when the connect fails.
# The older client awaits the cached promise with no reset, so one failed connect fails every later request.
export id=mongoose-client-promise-retry
export level=high
export names="mongoose-client.ts"
export template=skills/add/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts
export desc="the Mongoose client awaits a cached connect promise and never resets it after a failure, so one failed connect fails every later request"
export fix="wrap the await in try/catch, set cached.promise = null in the catch, and rethrow"

# Match a client that awaits cached.promise and has no reset of it.
check() {
  if has "$1" 'await cached.promise' && lacks "$1" 'cached.promise = null'; then
    at "$1" 'await cached.promise'
  fi
}

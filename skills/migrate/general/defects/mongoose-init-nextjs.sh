#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in c998466a: connectDB waits for every registered model's init() so unique indexes exist before the first write.
export id=mongoose-init-nextjs
export level=check
export names="mongoose-client.ts"
export template=skills/add/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts
export desc="connectDB does not call init() on the registered models, so a unique index may not exist when the first write lands; verify against your models"
export fix="after the connect, await Promise.all(conn.modelNames().map((name) => conn.model(name).init())) and import model modules before the first connectDB() call"

# Match a client that defines connectDB and never calls init(), ignoring comments.
check() {
  local text
  text=$(strip_comments "$1") || return 1
  case "$text" in
    *connectDB*)
      case "$text" in
        *'.init()'*) ;;
        *) echo "$1:$(line_of "$text" 'connectDB')" ;;
      esac
      ;;
  esac
}

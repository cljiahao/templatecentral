#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in c998466a: connectDB waits for every registered model's init() so unique indexes exist before the first write.
export id=mongoose-init-nextjs
export level=check
export names="*.ts *.js *.mjs *.cjs"
export content="mongoose.connect("
export template=skills/add/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts
export desc="the Mongoose client connects and does not call init() on the registered models, so a declared unique index may not exist when the first write lands; verify against your models"
export fix="after the connect, await Promise.all(conn.modelNames().map((name) => conn.model(name).init())) and import model modules before the first connect call"

# Match a client that calls mongoose.connect( and never calls init(), ignoring comments. Silent unless the project source declares a unique index.
check() {
  local text
  has_unique_index || return 0
  text=$(strip_comments "$1") || return 1
  case "$text" in
    *mongoose.connect\(*)
      case "$text" in
        *'.init()'*) ;;
        *) echo "$1:$(line_of "$text" 'mongoose.connect(')" ;;
      esac
      ;;
  esac
}

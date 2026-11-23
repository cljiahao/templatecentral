#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in c998466a: DatabaseModule awaits init() of every model on module init so unique indexes exist before the first write.
export id=mongoose-init-nestjs
export level=check
export names="*.ts"
export content="MongooseModule.forRoot"
export template=skills/add/database/typescript/nestjs-mongoose/template/src/database/database.module.ts
export desc="the module connects through MongooseModule.forRoot and does not call init() on the registered models, so a declared unique index may not exist when the first write lands; verify against your models"
export fix="implement OnModuleInit and await Promise.all(Object.values(this.connection.models).map((model) => model.init()))"

# Match a module that connects through MongooseModule.forRoot and never calls init(), ignoring comments. Silent unless the project source declares a unique index.
check() {
  local text
  has_unique_index || return 0
  text=$(strip_comments "$1") || return 1
  case "$text" in
    *MongooseModule.forRoot*)
      case "$text" in
        *'.init()'*) ;;
        *) echo "$1:$(line_of "$text" 'MongooseModule.forRoot')" ;;
      esac
      ;;
  esac
}

#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in c998466a: DatabaseModule awaits init() of every model on module init so unique indexes exist before the first write.
export id=mongoose-init-nestjs
export level=check
export names="database.module.ts"
export template=skills/add/database/typescript/nestjs-mongoose/template/src/database/database.module.ts
export desc="DatabaseModule does not call init() on the registered models, so a unique index may not exist when the first write lands; verify against your models"
export fix="implement OnModuleInit and await Promise.all(Object.values(this.connection.models).map((model) => model.init()))"

# Match a module that connects through MongooseModule.forRoot and never calls init().
check() {
  if has "$1" 'MongooseModule.forRoot' && lacks "$1" '.init()'; then
    at "$1" 'MongooseModule.forRoot'
  fi
}

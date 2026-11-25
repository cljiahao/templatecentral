#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984 (the older fixed literal below was replaced by a hash made at startup).
# The literal appeared in the NestJS auth services and the Python auth service of the older database leaves; no current template contains it.
export id=argon2-dummy-hash-literal
export level=check
export names="*.ts *.py"
export content="c29tZXNhbHRzb21lc2E"
export template=skills/add/database/typescript/nestjs-drizzle.md
export desc="the login path verifies a fixed literal Argon2 hash for unknown emails, so timing can differ from a real account's check; verify the cost matches your hasher settings"
export fix="build the dummy hash at startup with your own hasher, as the current template does, and verify it on the unknown-email path"

# Match a service that still carries the older literal's salt-and-digest text outside comments.
check() {
  local text
  text=$(strip_comments "$1") || return 1
  case "$text" in
    *"c29tZXNhbHRzb21lc2E\$Rdo0OMHkQXBTOTBqNCn0mPvBGiLxvGBIbxKZ0nJ0Aqo"*) echo "$1:$(line_of "$text" 'c29tZXNhbHRzb21lc2E')" ;;
  esac
}

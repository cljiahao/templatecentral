#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in a230bd1e: the stacks send the framing headers from the portal origin, not as fixed values.
# Limits: only the four files named in names are read, each by its template name. Another file that sets framing headers (a proxy, a gateway, a renamed file, nginx.conf) is not seen.
# A file that names a portal-origin marker anywhere outside comments counts as current, even if it still sends a fixed value. A project that must not be framed matches too: verify before changing.
# An unreadable candidate makes the run exit 2, never a clean result.
export id=frame-ancestors
export level=check
export names="next.config.ts security_headers.py security.setup.ts nginx.conf.template"
export content="X-Frame-Options x-frame-options frame-ancestors"
export template=skills/scaffold/nestjs/template/src/config/setups/security.setup.ts
export desc="the framing headers are fixed (X-Frame-Options or frame-ancestors 'none') and no portal origin is read, so an app that must be framed by its portal cannot be; this is a false match if the app must never be framed"
export fix="send frame-ancestors from the validated portal origin and X-Frame-Options only when framing is denied, per the portal framing guide"

# Match a framing file with a fixed X-Frame-Options or a fixed frame-ancestors 'none' and no portal-origin marker (PORTAL_ORIGIN, TC_FRAME_ANCESTORS), ignoring comments and case.
check() {
  local text lower n
  text=$(strip_comments "$1") || return 1
  lower=$(printf '%s\n' "$text" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *portal_origin*|*tc_frame_ancestors*) return 0 ;;
  esac
  n=$(printf '%s\n' "$lower" | awk 'index($0, "x-frame-options") || (index($0, "frame-ancestors") && index($0, "'"'"'none'"'"'")) { print NR; exit }')
  [ -n "$n" ] || return 0
  echo "$1:$n"
}

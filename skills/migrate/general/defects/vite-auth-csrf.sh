#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984: the Vite auth service sends X-CSRF-Token on login and logout.
# A CSRF header set in a shared fetch wrapper in another file still matches here and needs a check by hand. Level stays high because the file itself shows cookie mode: it sends credentials: 'include' and no Authorization header. A bearer-token client does neither, so it is not flagged.
export id=vite-auth-csrf
export level=high
export names="auth-service.ts"
export template=skills/add/auth/vite-react/template/src/features/auth/api/auth-service.ts
export desc="the Vite auth service posts login and logout with no CSRF token; this applies when the backend uses cookie-mode auth"
export fix="send csrfHeader() (X-CSRF-Token from the XSRF-TOKEN cookie) on the login and logout POSTs"

# Match a cookie-mode auth service with a logout call and no CSRF header helper, ignoring comments.
check() {
  local text
  text=$(strip_comments "$1") || return 1
  case "$text" in
    *Authorization*|*Bearer*) return 0 ;;
  esac
  case "$text" in
    *loginWithCredentials*/logout*include*) ;;
    *) return 0 ;;
  esac
  case "$text" in
    *csrfHeader*|*X-CSRF-Token*) return 0 ;;
  esac
  echo "$1:$(line_of "$text" '/logout')"
}

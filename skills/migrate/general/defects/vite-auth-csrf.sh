#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984: the Vite auth service sends X-CSRF-Token on login and logout.
# Applies to a project whose backend runs the cookie-mode auth (HttpOnly session cookie plus XSRF-TOKEN); a bearer-token backend needs no CSRF header.
export id=vite-auth-csrf
export level=high
export names="auth-service.ts"
export template=skills/add/auth/vite-react/template/src/features/auth/api/auth-service.ts
export desc="the Vite auth service posts login and logout with no CSRF token; this applies when the backend uses cookie-mode auth"
export fix="send csrfHeader() (X-CSRF-Token from the XSRF-TOKEN cookie) on the login and logout POSTs"

# Match an auth service with a logout call and no CSRF header helper.
check() {
  if has "$1" 'loginWithCredentials' && has "$1" '/logout' && lacks "$1" 'csrfHeader' && lacks "$1" 'X-CSRF-Token'; then
    at "$1" '/logout'
  fi
}

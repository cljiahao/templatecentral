#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in c998466a: the engine sets sslmode=verify-full outside dev.
# Matches also when TLS is set in the database URL, or when the database is not PostgreSQL (the setting does not apply there); verify before changing.
export id=sqlalchemy-tls-verify
export level=check
export names="session.py"
export template=skills/add/database/python/sqlalchemy/template/src/database/session.py
export desc="the SQLAlchemy engine sets no sslmode, so a PostgreSQL connection may not verify the server certificate; this is a false match if TLS is set in the URL or the database is not PostgreSQL"
export fix="pass connect_args with sslmode verify-full and sslrootcert outside dev, for PostgreSQL only"

# Match a session module that builds an engine (sync or async) and never mentions sslmode outside comments.
check() {
  local text pat
  text=$(strip_comments "$1") || return 1
  pat=
  case "$text" in
    *'create_async_engine('*) pat='create_async_engine(' ;;
  esac
  case "$text" in
    *'create_engine('*) pat='create_engine(' ;;
  esac
  [ -n "$pat" ] || return 0
  case "$text" in
    *sslmode*) ;;
    *) echo "$1:$(line_of "$text" "$pat")" ;;
  esac
}

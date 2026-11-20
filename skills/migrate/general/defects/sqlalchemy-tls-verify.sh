#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in c998466a: the engine sets sslmode=verify-full outside dev.
# Files are found by content (create_engine or create_async_engine), not by file name.
# Matches also when TLS is set in the database URL, or when the database is not PostgreSQL (the setting does not apply there); verify before changing.
export id=sqlalchemy-tls-verify
export level=check
export names="*.py"
export content="create_engine create_async_engine"
export template=skills/add/database/python/sqlalchemy/template/src/database/session.py
export desc="the SQLAlchemy engine sets no TLS argument, so a PostgreSQL connection may not verify the server certificate; this is a false match if TLS is set in the URL or the database is not PostgreSQL"
export fix="pass connect_args with sslmode verify-full and sslrootcert outside dev, for PostgreSQL only"

# Match a session module that builds an engine (sync or async, blanks before the paren allowed) and never sets a TLS argument (sslmode, sslrootcert, ssl_context, ssl) outside comments.
check() {
  local text n
  text=$(strip_comments "$1") || return 1
  n=$(printf '%s\n' "$text" | awk '/create_(async_)?engine[ \t]*\(/ { print NR; exit }')
  [ -n "$n" ] || return 0
  case "$text" in
    *sslmode*|*sslrootcert*|*ssl_context*|*ssl=*|*\"ssl\"*|*\'ssl\'*) ;;
    *) echo "$1:$n" ;;
  esac
}

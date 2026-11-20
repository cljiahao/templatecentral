#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in c998466a: the engine sets sslmode=verify-full outside dev.
# Matches also when TLS is set in the database URL, or when the database is not PostgreSQL (the setting does not apply there); verify before changing.
export id=sqlalchemy-tls-verify
export level=check
export names="session.py"
export template=skills/add/database/python/sqlalchemy/template/src/database/session.py
export desc="the SQLAlchemy engine sets no sslmode, so a PostgreSQL connection may not verify the server certificate; this is a false match if TLS is set in the URL or the database is not PostgreSQL"
export fix="pass connect_args with sslmode verify-full and sslrootcert outside dev, for PostgreSQL only"

# Match a session module that builds an engine and never mentions sslmode.
check() {
  if has "$1" 'create_engine(' && lacks "$1" 'sslmode'; then
    at "$1" 'create_engine('
  fi
}

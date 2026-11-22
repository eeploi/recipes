#!/usr/bin/env bash
# Probe: PostgreSQL, each cluster. A few settings, as PostgreSQL reads them, after every included
# file and ALTER SYSTEM (postgres -C, as the postgres user). Those in the list only: its config
# can hold a password, such as primary_conninfo's. No PostgreSQL: no lines. PROBES.md.
# Lines: cluster <version>/<name> <setting> <value>; none for an empty value. cluster
# <version>/<name> unreadable when postgres can't read that cluster's config, such as one left over.
set -euo pipefail
# The settings whose values are safe to show, each one shown.
safe=(listen_addresses port ssl password_encryption max_connections)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

shopt -s nullglob
for conf in /etc/postgresql/*/*/postgresql.conf; do
  cluster=${conf#/etc/postgresql/}
  cluster=${cluster%/postgresql.conf}
  [[ $cluster =~ ^[0-9]+/[A-Za-z0-9_.-]+$ ]] || continue
  postgres=/usr/lib/postgresql/${cluster%%/*}/bin/postgres
  [ -x "$postgres" ] || continue
  for setting in "${safe[@]}"; do
    # D-17: the config on disk, not the running server.
    value=$(runuser -u postgres -- "$postgres" -C "$setting" --config-file="$conf" 2> /dev/null) \
      || { echo "cluster $cluster unreadable"; continue 2; }
    # A value is one line: a line break or other control character shows as a space.
    value=${value//[[:cntrl:]]/ }
    echo "cluster $cluster $setting ${value:-none}"
  done
done

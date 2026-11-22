#!/usr/bin/env bash
# Probe: MariaDB or MySQL. A few server options, as the server reads them, after every included
# file (mariadbd or mysqld --print-defaults): for each the last value, as the server takes it.
# Those in the list only. No MariaDB or MySQL server: no lines. README, Probes.
# Lines: option <name> <value>, the name with - for _; on for an option without a value.
set -euo pipefail
# The settings whose values are safe to show. The server takes - and _ alike.
safe=(bind-address port skip-networking local-infile max-connections require-secure-transport skip-name-resolve)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

server=''
for bin in /usr/sbin/mariadbd /usr/sbin/mysqld; do
  if [ -x "$bin" ]; then server=$bin; break; fi
done
[ -n "$server" ] || exit 0
# D-17: the config on disk, not the running server.
defaults=$("$server" --print-defaults 2> /dev/null)
# The first line says what follows; then the options, split by spaces.
tail -n +2 <<< "$defaults" | tr ' ' '\n' | awk -v safe="${safe[*]}" '
  BEGIN { n = split(safe, order, " "); for (i = 1; i <= n; i++) known[order[i]] = 1 }
  /^--/ {
    name = substr($0, 3); value = "on"
    if (index(name, "=")) { value = substr(name, index(name, "=") + 1); name = substr(name, 1, index(name, "=") - 1) }
    gsub(/_/, "-", name)
    if (name in known && value != "") last[name] = value
  }
  END { for (i = 1; i <= n; i++) if (order[i] in last) print "option " order[i] " " last[order[i]] }'

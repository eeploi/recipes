#!/usr/bin/env bash
# Probe: Redis. Where redis-server listens, and whether it asks for a password. D-19: Redis prints
# its config only to a client that logs in, so no setting is read. No Redis: no lines.
# PROBES.md.
# Lines: listen <address:port> for each, or listen none; password <yes|no|unknown>, from a PING to
# the first address, without a password.
set -euo pipefail
# The settings whose values are safe to show (redis.conf).
safe=(bind port protected-mode unixsocket maxmemory maxmemory-policy)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

command -v redis-server > /dev/null || exit 0
command -v ss > /dev/null || exit 0
sockets=$(ss -tlnpH 2> /dev/null)
mapfile -t listens < <(awk '/users:\(\("redis-server",/ { print $4 }' <<< "$sockets" | LC_ALL=C sort -u)
if [ "${#listens[@]}" -eq 0 ]; then
  echo 'listen none'
  exit 0
fi
printf 'listen %s\n' "${listens[@]}"
command -v redis-cli > /dev/null || exit 0
address=${listens[0]}
port=${address##*:}
host=${address%:*}
host=${host#[}
host=${host%]}
host=${host%%%*}
case "$host" in '*' | 0.0.0.0) host=127.0.0.1 ;; '::') host=::1 ;; esac
reply=$(timeout 5 redis-cli -h "$host" -p "$port" PING 2> /dev/null) || true
case "$reply" in
  PONG) echo 'password no' ;;
  *NOAUTH*) echo 'password yes' ;;
  *) echo 'password unknown' ;;
esac

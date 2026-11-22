#!/usr/bin/env bash
# Probe: PHP-FPM, each version installed. Per pool the settings FPM reads, after every pool file
# (php-fpm<v> -tt), and a few PHP settings FPM's PHP reads, after every ini file (php-fpm<v> -i).
# Those in the lists only: a pool's env[] and php_value[] can hold secrets. No PHP-FPM: no lines.
# PROBES.md.
# Lines: pool <version> <pool> <setting> <value>, ini <version> <setting> <value>.
set -euo pipefail
pool_safe=(user group listen listen.owner listen.group listen.mode pm pm.max_children pm.max_requests)
ini_safe=(expose_php session.upload_progress.enabled opcache.validate_permission)
# The settings whose values are safe to show: the pool settings, then the ini settings.
[ "${1:-}" != --safe ] || { printf '%s\n' "${pool_safe[@]}" "${ini_safe[@]}"; exit 0; }

shopt -s nullglob
for fpm in /usr/sbin/php-fpm[0-9]*; do
  version=${fpm#/usr/sbin/php-fpm}
  [[ $version =~ ^[0-9]+\.[0-9]+$ ]] || continue
  # D-17: the config on disk, not the running FPM. -tt prints it to stderr, with a NOTICE line each.
  pools=$("$fpm" -tt 2>&1)
  awk -v version="$version" -v safe=" ${pool_safe[*]} " '
    /NOTICE: \[.*\]$/ { pool = $0; sub(/.*NOTICE: \[/, "", pool); sub(/\]$/, "", pool); next }
    pool != "" && pool != "global" && / NOTICE:[[:space:]]+[a-z][a-z._]* = / {
      line = $0; sub(/.*NOTICE:[[:space:]]+/, "", line)
      key = line; sub(/ = .*/, "", key)
      value = line; sub(/^[^ ]* = /, "", value)
      if (index(safe, " " key " ") && value != "" && value != "undefined") print "pool " version " " pool " " key " " value
    }' <<< "$pools"
  ini=$("$fpm" -i 2> /dev/null)
  awk -v version="$version" -v safe=" ${ini_safe[*]} " '$2 == "=>" && $4 == "=>" && index(safe, " " $1 " ") { print "ini " version " " $1 " " $3 }' <<< "$ini"
done

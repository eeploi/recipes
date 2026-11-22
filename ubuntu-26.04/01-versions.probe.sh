#!/usr/bin/env bash
# Probe: versions. The packages installed of nginx, PHP-FPM, PostgreSQL, MariaDB, MySQL, Redis,
# Node.js, npm and Composer, and the npm and Composer step 1 installs in /usr/local, read from
# their files: neither runs. None of them: no lines. README, Probes.
# Lines: package <name> <version>, npm <version>, composer <version>.
set -euo pipefail
# No settings.
[ "${1:-}" != --safe ] || exit 0

if command -v dpkg-query > /dev/null; then
  # dpkg-query fails on a name that matches no package, and prints the others.
  # shellcheck disable=SC2016 # the ${} is dpkg-query's
  installed=$(dpkg-query -W -f '${db:Status-Abbrev} ${Package} ${Version}\n' nginx 'php*-fpm' 'postgresql-[0-9]' \
    'postgresql-[0-9][0-9]' mariadb-server mysql-server redis-server nodejs npm composer 2> /dev/null) || true
  awk '$1 == "ii" && NF == 3 { print "package " $2 " " $3 }' <<< "$installed"
fi

version='^[0-9]+\.[0-9]+\.[0-9]+([.+~-][0-9A-Za-z.+~-]*)?$'
npm=/usr/local/lib/node_modules/npm/package.json
if [ -f "$npm" ]; then
  v=$(sed -n 's/^  "version": "\([^"]*\)",*$/\1/p' "$npm" | head -n 1)
  [[ ! $v =~ $version ]] || echo "npm $v"
fi
# Composer's phar holds its version as a constant, in plain text.
composer=/usr/local/bin/composer
if [ -f "$composer" ]; then
  v=$(grep -aoE -m 1 "const VERSION = '[^']+'" "$composer" | head -n 1 | sed "s/.*= '//; s/'\$//") || true
  [[ ! $v =~ $version ]] || echo "composer $v"
fi

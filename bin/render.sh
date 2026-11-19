#!/usr/bin/env bash
# Prints the script a server runs: the files in ubuntu-26.04/steps in order, an empty line between
# each, with example values. For CI, so shellcheck sees the code as it runs. A {name} alone on a
# line stands for lines eeploi renders itself and is left out here.
# Usage: bin/render.sh [--no-first-boot]
set -euo pipefail
cd "$(dirname "$0")/.."

skip=''
[ "${1:-}" = --no-first-boot ] && skip='^first-boot/'

first=1
while IFS= read -r file; do
  case "$file" in '' | '#'*) continue ;; esac
  if [ -n "$skip" ] && [[ "$file" =~ $skip ]]; then continue; fi
  [ "$first" -eq 1 ] || echo
  first=0
  sed -E \
    -e 's/^\{[a-z_]+\}$/:/' \
    -e 's/\{user\}/deploy/g; s/\{port\}/2222/g; s/\{php\}/8.4/g; s/\{version\}/26.04/g' \
    -e 's/\{name\}/shop.example/g; s/\{report_url\}/https:\/\/eeploi.example\/report/g' \
    -e 's/\{ranges\}/192.0.2.0\/24 198.51.100.0\/24/g; s/\{database\}/mariadb-server/g; s/\{npm\}/11.0.0/g' \
    -e 's/\{helper_path\}/\/usr\/local\/bin\/eeploi-helper/g; s/\{codename\}/resolute/g' \
    "$file"
done < ubuntu-26.04/steps

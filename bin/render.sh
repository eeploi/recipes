#!/usr/bin/env bash
# Prints the script a server runs: the files in ubuntu-26.04/steps in order, an empty line between
# each, with example values. For CI, so shellcheck sees the code as it runs. A {name} alone on a
# line stands for lines eeploi renders itself and is left out here, except {php_source}, which
# gets php-source.sh.
# Usage: bin/render.sh [--no-first-boot | --checks]
#   --checks  the values, then the check of each step, as one script
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:-}

render() {
  sed -E -e '/^\{php_source\}$/{' -e 'r ubuntu-26.04/php-source.sh' -e 'd' -e '}' "$1" | sed -E \
    -e 's/^\{[a-z_]+\}$/:/' \
    -e 's/\{user\}/deploy/g; s/\{port\}/2222/g; s/\{php\}/8.4/g; s/\{version\}/26.04/g' \
    -e 's/\{name\}/shop.example/g; s/\{report_url\}/https:\/\/eeploi.example\/report/g' \
    -e 's/\{ranges\}/192.0.2.0\/24 198.51.100.0\/24/g; s/\{database\}/mariadb-server/g; s/\{npm\}/11.0.0/g' \
    -e 's/\{helper_path\}/\/usr\/local\/bin\/eeploi-helper/g; s/\{codename\}/resolute/g'
}

first=1
emit() {
  [ "$first" -eq 1 ] || echo
  first=0
  render "$1"
}

if [ "$mode" = --checks ]; then
  echo '#!/usr/bin/env bash'
  first=0
  emit stack/values.sh
fi

while IFS= read -r file || [ -n "$file" ]; do
  case "$file" in '' | '#'*) continue ;; esac
  if [ "$mode" = --no-first-boot ] && [[ "$file" == first-boot/* ]]; then continue; fi
  if [ "$mode" = --checks ]; then
    check=${file%.sh}.check.sh
    [ -f "$check" ] && emit "$check"
  else
    emit "$file"
  fi
done < ubuntu-26.04/steps

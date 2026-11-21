#!/usr/bin/env bash
# Prints the script a server runs: the files in ubuntu-26.04/steps in order, an empty line between
# each, with example values. For CI, so shellcheck sees the code as it runs. A {name} alone on a
# line stands for lines eeploi renders itself and is left out here (an empty line), except
# {php_source}, which gets php-source.sh, as for any other PHP than Ubuntu's.
# RENDER_PHP sets the PHP version, 8.4 by default; Ubuntu 26.04's own, 8.5, leaves out
# php-source.sh, as eeploi does.
# Usage: bin/render.sh [--no-first-boot | --checks | --step FILE | --check FILE]
#   --checks        the values, then the check of each step, each on its own, as one script
#   --step FILE     start.sh, the values and that one step, to run on its own (bin/run-twice.sh),
#                   with only the values the helper fills on a live server: any other is left over
#   --check FILE    as --checks, with only that step's check
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:-}
step=${2:-}
case "$mode" in --step | --check) [ -f "$step" ] || { echo "$mode needs a step file" >&2; exit 2; } ;; esac

left=0
php=${RENDER_PHP:-8.4}
[[ $php =~ ^[0-9]\.[0-9]$ ]] || { echo "RENDER_PHP is no PHP version: $php" >&2; exit 2; }
php_source=ubuntu-26.04/php-source.sh
[ "$php" != 8.5 ] || php_source=/dev/null

# The values the helper fills on a live server, the only ones in --step. bin/check-layout.sh
# renders each always step with --step, so this is the one list of them.
helper_values="s/\{user\}/deploy/g; s/\{port\}/10022/g; s/\{php\}/$php/g; s/\{version\}/26.04/g; s/\{name\}/shop.example/g"

render() {
  local out
  if [ "$mode" = --step ]; then
    out=$(sed -E -e "$helper_values" "$1")
  else
    out=$(sed -E -e '/^\{php_source\}$/{' -e "r $php_source" -e 'd' -e '}' "$1" | sed -E \
      -e 's/^\{[a-z_]+\}$//' -e "$helper_values" \
      -e 's/\{report_url\}/https:\/\/eeploi.example\/report/g' \
      -e 's/\{ranges\}/192.0.2.0\/24 198.51.100.0\/24/g; s/\{database\}/mariadb-server/g; s/\{npm\}/11.21.3/g' \
      -e 's/\{helper_path\}/\/usr\/local\/sbin\/eeploi-helper/g; s/\{codename\}/resolute/g')
  fi
  printf '%s\n' "$out"
  # A {name} left over is a value this script doesn't know. ${name} and $x{name} are bash.
  # shellcheck disable=SC2016 # the $ is in a regex
  while IFS= read -r placeholder; do
    echo "$1: $placeholder is not replaced" >&2
    left=1
  done < <(grep -oE '(^|[^$A-Za-z0-9_])\{[a-z_]+\}' <<< "$out" | grep -oE '\{[a-z_]+\}' || true)
}

first=1
emit() {
  [ "$first" -eq 1 ] || echo
  first=0
  render "$1"
}

if [ "$mode" = --step ]; then
  for file in stack/start.sh stack/values.sh "$step"; do emit "$file"; done
  exit "$left"
fi

# Each check runs in its own subshell under set -e, so any line that fails fails it, and says so
# on its own, with the command that failed.
checks=0
found=0
case "$mode" in --checks | --check) checks=1 ;; esac
if [ "$checks" -eq 1 ]; then
  echo '#!/usr/bin/env bash'
  render stack/values.sh
  cat <<'HEAD'
fail=0
result() { if [ "$1" -eq 0 ]; then echo "ok $2"; else echo "failed $2"; fail=1; fi; }
HEAD
fi

while IFS= read -r file || [ -n "$file" ]; do
  case "$file" in '' | '#'*) continue ;; esac
  if [ "$mode" = --no-first-boot ] && [[ "$file" == first-boot/* ]]; then continue; fi
  if [ "$checks" -eq 1 ]; then
    [ "$mode" = --checks ] || [ "$file" = "$step" ] || continue
    check=${file%.sh}.check.sh
    [ -f "$check" ] || continue
    found=1
    cat <<'OPEN'

(
set -euo pipefail
trap 'echo "  $BASH_COMMAND" >&2' ERR
OPEN
    render "$check"
    echo "); result \$? $check"
  else
    emit "$file"
  fi
done < ubuntu-26.04/steps

[ "$mode" != --check ] || [ "$found" -eq 1 ] || { echo "$step has no check in ubuntu-26.04/steps" >&2; exit 2; }
# shellcheck disable=SC2016 # the $ is for the checks script
[ "$checks" -eq 0 ] || echo 'exit "$fail"'
exit "$left"

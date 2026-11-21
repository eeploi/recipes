#!/usr/bin/env bash
# Runs each always step from markers twice, then its check, as root in a throwaway container: a
# step that is safe on a live server leaves /etc the same on a second run, and fails no unit.
# For CI only.
# Usage: bin/run-twice.sh [FILE...]   those steps instead of the always ones
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A step or check runs as the helper runs it (recipe-run): from /, with its PATH and a clean environment.
as_helper() { (cd / && exec env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LC_ALL=C TMPDIR=/tmp bash "$1") < /dev/null; }

failed() { systemctl list-units --state=failed --plain --no-legend | awk '{ print $1 }' | LC_ALL=C sort; }

fail=0
while read -r file; do
  if ! bin/render.sh --step "$file" > "$tmp/step" || ! bin/render.sh --check "$file" > "$tmp/check"; then
    echo "$file: does not render"
    fail=1
    continue
  fi
  failed > "$tmp/failed.before"
  for run in 1 2; do
    if ! as_helper "$tmp/step"; then
      echo "$file: run $run failed"
      fail=1
      continue 2
    fi
    bin/etc-state.sh > "$tmp/etc.$run"
  done
  new=$(failed | LC_ALL=C comm -13 "$tmp/failed.before" - | paste -sd ' ' -)
  if [ -n "$new" ]; then
    echo "$file: left failed: $new"
    fail=1
  elif ! diff "$tmp/etc.1" "$tmp/etc.2"; then
    echo "$file: the second run changed /etc"
    fail=1
  elif as_helper "$tmp/check"; then
    echo "$file: twice, check ok"
  else
    echo "$file: check failed after two runs"
    fail=1
  fi
done < <(if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else awk '$1 == "always" { print $2 }' markers; fi)

exit "$fail"

#!/usr/bin/env bash
# Runs each check in ubuntu-26.04/steps on its own, as root in a throwaway container, and fails one
# that changes /etc, or stops, starts or restarts fail2ban or nginx, whether the check passes or
# not: a check is read-only. A check that fails stops at its failing line, so lines after it are not
# tested here. For CI only.
# Usage: bin/checks-read-only.sh [FILE...]   the checks of those steps instead of all
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=bin/helper-env.sh
. bin/helper-env.sh

fail=0
while IFS= read -r file; do
  check=${file%.sh}.check.sh
  [ -f "$check" ] || continue
  if ! bin/render.sh --check "$file" > "$tmp/check"; then
    echo "$check: does not render"
    fail=1
    continue
  fi
  state > "$tmp/before"
  as_helper "$tmp/check" > /dev/null 2>&1 || true
  state > "$tmp/after"
  if diff "$tmp/before" "$tmp/after"; then
    echo "$check: read-only"
  else
    echo "$check: changed the server"
    fail=1
  fi
done < <(if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else grep -E '/[0-9]{2}-[^/]*\.sh$' ubuntu-26.04/steps; fi)

exit "$fail"

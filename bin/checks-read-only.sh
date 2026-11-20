#!/usr/bin/env bash
# Runs each check in ubuntu-*/steps on its own, as root in a throwaway container, and fails one
# that changes /etc or the state of a unit, whether the check passes or not: a check is read-only.
# For CI only.
# Usage: bin/checks-read-only.sh [FILE...]   the checks of those steps instead of all
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state() {
  bin/etc-state.sh
  systemctl list-units --all --plain --no-legend | awk '{ print $1, $2, $3, $4 }' | LC_ALL=C sort
}

fail=0
while read -r file; do
  [ -f "${file%.sh}.check.sh" ] || continue
  bin/render.sh --check "$file" > "$tmp/check"
  state > "$tmp/before"
  bash "$tmp/check" < /dev/null > /dev/null 2>&1 || true
  state > "$tmp/after"
  if diff "$tmp/before" "$tmp/after"; then
    echo "${file%.sh}.check.sh: read-only"
  else
    echo "${file%.sh}.check.sh: changed the server"
    fail=1
  fi
done < <(if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else grep -hE '/[0-9]{2}-[^/]*\.sh$' ubuntu-*/steps; fi)

exit "$fail"

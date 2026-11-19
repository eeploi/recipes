#!/usr/bin/env bash
# Runs each always step from markers twice, then its check, as root in a throwaway container: a
# step that is safe on a live server leaves /etc the same on a second run. For CI only.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Every path in /etc with its type, mode, owner and link target, and every file's content.
etc() {
  find /etc -xdev -printf '%p %y %m %u:%g %l\n' | LC_ALL=C sort
  find /etc -xdev -type f -exec sha256sum {} + | LC_ALL=C sort -k2
}

fail=0
while read -r marker file || [ -n "$marker" ]; do
  [ "$marker" = always ] || continue
  if ! bin/render.sh --step "$file" > "$tmp/step" || ! bin/render.sh --check "$file" > "$tmp/check"; then
    echo "$file: does not render"
    fail=1
    continue
  fi
  for run in 1 2; do
    if ! bash "$tmp/step" < /dev/null; then
      echo "$file: run $run failed"
      fail=1
      continue 2
    fi
    etc > "$tmp/etc.$run"
  done
  if ! diff "$tmp/etc.1" "$tmp/etc.2"; then
    echo "$file: the second run changed /etc"
    fail=1
  elif bash "$tmp/check" < /dev/null; then
    echo "$file: twice, check ok"
  else
    echo "$file: check failed after two runs"
    fail=1
  fi
done < markers

exit "$fail"

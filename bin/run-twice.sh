#!/usr/bin/env bash
# Runs each always step from markers twice, then its check, as root in a throwaway container: a
# step that is safe on a live server leaves the same server on a second run. For CI only.
set -euo pipefail
cd "$(dirname "$0")/.."

script=$(mktemp)
check=$(mktemp)
trap 'rm -f "$script" "$check"' EXIT

fail=0
while read -r marker file || [ -n "$marker" ]; do
  [ "$marker" = always ] || continue
  bin/render.sh --step "$file" > "$script"
  bin/render.sh --check "$file" > "$check"
  for run in 1 2; do
    if ! bash "$script" < /dev/null; then
      echo "$file: run $run failed"
      fail=1
      continue 2
    fi
  done
  if bash "$check" < /dev/null; then echo "$file: twice, check ok"; else echo "$file: check failed after two runs"; fail=1; fi
done < markers

exit "$fail"

#!/usr/bin/env bash
# Checks the repo layout: every file in ubuntu-*/steps exists, and every step in it
# sets STEP=, has its .check.sh next to it and is in the README table.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# Steps without a check, by name. They only run at the first boot eeploi creates, and talk to the
# network (the helper download, the report to eeploi), so a read-only check has nothing to read.
NO_CHECK='first-boot/00-helper-download.sh first-boot/11-report.sh'

fail=0
bad() { echo "$1: $2"; fail=1; }

# shellcheck disable=SC2094 # bad() only prints
for list in ubuntu-*/steps; do
  while IFS= read -r file || [ -n "$file" ]; do
    case "$file" in '' | '#'*) continue ;; esac

    if [ ! -f "$file" ]; then
      bad "$list" "$file does not exist"
      continue
    fi

    name=${file##*/}
    case "$name" in [0-9][0-9]-*.sh) ;; *) continue ;; esac # start.sh and values.sh are no steps

    grep -q '^STEP=' "$file" || bad "$file" "sets no STEP="
    case " $NO_CHECK " in
      *" $file "*) ;;
      *) [ -f "${file%.sh}.check.sh" ] || bad "$file" "has no ${name%.sh}.check.sh" ;;
    esac
    grep -qF "\`$file\`" README.md || bad "$file" "is not in the README table"
  done < "$list"
done

[ "$fail" -eq 0 ] && echo "layout ok"
exit "$fail"

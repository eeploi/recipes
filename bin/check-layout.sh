#!/usr/bin/env bash
# Checks the repo layout: every file in ubuntu-*/steps exists, and every step in it
# sets STEP=, has its .check.sh next to it, has one marker in markers and is in the README table.
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
    case $(awk -v f="$file" '$2 == f' markers | wc -l | tr -d ' ') in
      0) bad "$file" "has no marker in markers" ;;
      1) ;;
      *) bad "$file" "has more than one marker in markers" ;;
    esac
    grep -qF "\`$file\`" README.md || bad "$file" "is not in the README table"
  done < "$list"
done

# Each line in markers: a known marker and a step that a list of steps runs.
# shellcheck disable=SC2094 # bad() only prints
while read -r marker file rest || [ -n "$marker" ]; do
  case "$marker" in '' | '#'*) continue ;; esac
  case "$marker" in first-boot | always | window) ;; *) bad markers "$marker is no marker (first-boot, always, window)" ;; esac
  [ -z "$rest" ] || bad markers "$file: more than a marker and a file"
  grep -qxF "$file" ubuntu-*/steps || bad markers "$file is in no list of steps"
  # A step without a check, or one for a server eeploi creates, never runs on a live server.
  case " $NO_CHECK " in *" $file "*) no_check=1 ;; *) no_check=0 ;; esac
  if [ "$marker" != first-boot ] && { [[ "$file" == first-boot/* ]] || [ "$no_check" -eq 1 ]; }; then
    bad markers "$file can only be first-boot"
  fi
done < markers

[ "$fail" -eq 0 ] && echo "layout ok"
exit "$fail"

#!/usr/bin/env bash
# Checks the repo layout: every file in ubuntu-*/steps exists, and every step in it
# sets STEP=, has its .check.sh next to it, has one marker in markers and is in the README table.
# An always step holds only the values the helper fills.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# Steps without a check, by name. They only run at the first boot eeploi creates, and talk to the
# network (the helper download, the report to eeploi), so a read-only check has nothing to read.
NO_CHECK='first-boot/00-helper-download.sh first-boot/11-report.sh'

# The values the helper fills in a step it runs on a live server. It refuses any other {name}.
HELPER_VALUES='{user} {port} {php} {version} {name}'

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
    case $(awk -v f="$file" '$1 !~ /^#/ && $2 == f' markers | wc -l | tr -d ' ') in
      0) bad "$file" "has no marker in markers" ;;
      1) ;;
      *) bad "$file" "has more than one marker in markers" ;;
    esac
    grep -qF "\`$file\`" README.md || bad "$file" "is not in the README table"
  done < "$list"
done

# Each line in markers: a known marker, a step that a list of steps runs, and known flags.
# shellcheck disable=SC2094 # bad() only prints
while read -r marker file flags rest || [ -n "$marker" ]; do
  case "$marker" in '' | '#'*) continue ;; esac
  case "$marker" in first-boot | always | window) ;; *) bad markers "$marker is no marker (first-boot, always, window)" ;; esac
  [ -z "$rest" ] || bad markers "$file: more than a marker, a file and flags"
  IFS=, read -ra flag_list <<< "$flags"
  for flag in ${flag_list[@]+"${flag_list[@]}"}; do
    case "$flag" in security | needs-restart | needs-reboot) ;; *) bad markers "$file: $flag is no flag (security, needs-restart, needs-reboot)" ;; esac
  done
  grep -qxF "$file" ubuntu-*/steps || bad markers "$file is in no list of steps"
  # A step without a check, or one for a server eeploi creates, never runs on a live server.
  case " $NO_CHECK " in *" $file "*) no_check=1 ;; *) no_check=0 ;; esac
  if [ "$marker" != first-boot ] && { [[ "$file" == first-boot/* ]] || [ "$no_check" -eq 1 ]; }; then
    bad markers "$file can only be first-boot"
  fi
  # A {name} as bin/render.sh finds one: ${name} and $x{name} are bash.
  if [ "$marker" = always ] && [ -f "$file" ]; then
    # shellcheck disable=SC2016 # the $ is in a regex
    while IFS= read -r placeholder; do
      case " $HELPER_VALUES " in
        *" $placeholder "*) ;;
        *) bad "$file" "is always, and the helper does not fill $placeholder (only $HELPER_VALUES)" ;;
      esac
    done < <(grep -oE '(^|[^$A-Za-z0-9_])\{[a-z_]+\}' "$file" | grep -oE '\{[a-z_]+\}' | sort -u)
  fi
done < markers

[ "$fail" -eq 0 ] && echo "layout ok"
exit "$fail"

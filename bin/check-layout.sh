#!/usr/bin/env bash
# Checks the repo layout: every file in ubuntu-*/steps has a path the helper takes, exists and is no
# link, and every step in it
# sets STEP=, has its .check.sh next to it, has one marker in markers and is in the README table.
# An always step holds only the values the helper fills (bin/render.sh --step).
set -uo pipefail
export LC_ALL=C # the path rule below matches ASCII only, as the helper's
cd "$(dirname "$0")/.." || exit 1

# Steps without a check, by name. They only run at the first boot eeploi creates, and talk to the
# network (the helper download, the report to eeploi), so a read-only check has nothing to read.
NO_CHECK='first-boot/00-helper-download.sh first-boot/11-report.sh'

# The helper's rule for a path in a manifest (recipe-run), as in bin/release.sh.
part='[A-Za-z0-9_][A-Za-z0-9._-]*'
path_name="^$part(/$part)*\$"

fail=0
bad() { echo "$1: $2"; fail=1; }

# shellcheck disable=SC2094 # bad() only prints
for list in ubuntu-*/steps; do
  while IFS= read -r file || [ -n "$file" ]; do
    case "$file" in '' | '#'*) continue ;; esac

    if ! [[ "$file" =~ $path_name ]]; then
      bad "$list" "$file is no path the helper takes: each part $part"
      continue
    fi
    if [ ! -f "$file" ]; then
      bad "$list" "$file does not exist"
      continue
    fi
    if [ -L "$file" ]; then
      bad "$list" "$file is a link"
      continue
    fi

    name=${file##*/}
    case "$name" in [0-9][0-9]-*.sh) ;; *) continue ;; esac # start.sh and values.sh are no steps

    grep -q '^STEP=' "$file" || bad "$file" "sets no STEP="
    case " $NO_CHECK " in
      *" $file "*) ;;
      *)
        check=${file%.sh}.check.sh
        [ -f "$check" ] || bad "$file" "has no ${check##*/}"
        [ ! -L "$check" ] || bad "$check" "is a link"
        ;;
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
  # On a live server the helper fills only the values bin/render.sh --step fills, and refuses any other.
  if [ "$marker" = always ] && [ -f "$file" ] && ! bin/render.sh --step "$file" > /dev/null; then
    bad "$file" "is always, and holds a value the helper does not fill"
  fi
done < markers

[ "$fail" -eq 0 ] && echo "layout ok"
exit "$fail"

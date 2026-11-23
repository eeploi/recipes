#!/usr/bin/env bash
# Checks the repo layout: every file in ubuntu-*/steps has a path the helper takes, exists and is no
# link, and every step in it sets STEP=, has its .check.sh next to it, has one marker in markers
# and is in the README table.
# An always step holds only the values the helper fills (bin/render.sh --step). Each list of steps
# has a list of probes, whose probes are named, listed and in PROBES.md as below. Every D-n a
# comment names is an entry in DECISIONS.md, numbered in order.
set -uo pipefail
export LC_ALL=C # the path rule below matches ASCII only, as the helper's
cd "$(dirname "$0")/.." || exit 1

# Steps without a check, by name. They only run at the first boot eeploi creates, and talk to the
# network (the helper download, the report to eeploi), so a read-only check has nothing to read.
NO_CHECK='first-boot/00-helper-download.sh first-boot/11-report.sh'

# The helper's rule for a path in a manifest (recipe-run), as in bin/build-release.sh.
part='[A-Za-z0-9_][A-Za-z0-9._-]*'
path_name="^$part(/$part)*\$"

fail=0
bad() { echo "$1: $2"; fail=1; }
# entry_ok LIST FILE: FILE, an entry of LIST, has a path the helper takes, exists and is no link.
entry_ok() {
  if ! [[ "$2" =~ $path_name ]]; then bad "$1" "$2 is no path the helper takes: each part $part"; return 1; fi
  [ -f "$2" ] || { bad "$1" "$2 does not exist"; return 1; }
  [ ! -L "$2" ] || { bad "$1" "$2 is a link"; return 1; }
}

# shellcheck disable=SC2094 # bad() only prints
for list in ubuntu-*/steps; do
  while IFS= read -r file || [ -n "$file" ]; do
    case "$file" in '' | '#'*) continue ;; esac
    entry_ok "$list" "$file" || continue

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

# Every list of steps has a list of probes next to it. Each probe in it has a path the helper
# takes, exists, is no link, is named NN-name.probe.sh with a name no other probe in the list has,
# holds no {name} value (nothing fills it) and is in the probe table in PROBES.md. Every probe in the
# repo is in a list.
listed=' '
for steps in ubuntu-*/steps; do
  list=${steps%/steps}/probes
  [ -f "$list" ] || { bad "$list" "does not exist"; continue; }
  names=' '
  # shellcheck disable=SC2094 # bad() only prints
  while IFS= read -r file || [ -n "$file" ]; do
    case "$file" in '' | '#'*) continue ;; esac
    entry_ok "$list" "$file" || continue
    [[ "$file" =~ /[0-9][0-9]-([a-z0-9-]+)\.probe\.sh$ ]] || { bad "$list" "$file is not named NN-name.probe.sh"; continue; }
    name=${BASH_REMATCH[1]}
    case "$names" in *" $name "*) bad "$list" "$file: another probe is named $name" ;; esac
    names+="$name "
    listed+="$file "
    # shellcheck disable=SC2016 # the $ is in a regex
    ! grep -qE '(^|[^$A-Za-z0-9_])\{[a-z_]+\}' "$file" || bad "$file" "holds a {name} value, which nothing fills in a probe"
    grep -qF "\`$file\`" PROBES.md || bad "$file" "is not in the probe table in PROBES.md"
  done < "$list"
done
while IFS= read -r file; do
  case "$listed" in *" $file "*) ;; *) bad "$file" "is in no list of probes" ;; esac
done < <(find first-boot stack ubuntu-* -name '*.probe.sh' | LC_ALL=C sort)

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

# DECISIONS.md numbers its entries D-1, D-2 … in order, each once, each heading as `## D-n: title`.
# Every file an entry's Where names has a D-n comment, and every D-n a comment names (in a script,
# a workflow, markers or a list of steps) is an entry. Files, not git: the release build runs this
# in an extracted tree.
grep -nE '^## D-' DECISIONS.md | grep -vE '^[0-9]+:## D-[0-9]+: ' | while IFS=: read -r line _; do
  echo "DECISIONS.md:$line: no heading ## D-n: title"
done | grep . && fail=1
ids=$(sed -n 's/^## \(D-[0-9]*\): .*/\1/p' DECISIONS.md)
n=0
for id in $ids; do
  n=$((n + 1))
  [ "$id" = "D-$n" ] || { bad DECISIONS.md "$id where D-$n comes"; break; }
done
known=" ${ids//$'\n'/ } "
while read -r id file; do
  [ -f "$file" ] || { bad DECISIONS.md "$id: Where names $file, which does not exist"; continue; }
  grep -qE "#.*$id:" "$file" || bad "$file" "has no $id comment, which DECISIONS.md names it for"
done < <(awk '/^## D-[0-9]+: / { id = substr($2, 1, length($2) - 1) }
  /^- \*\*Where:\*\* / { n = split($0, f, "`"); for (i = 2; i <= n; i += 2) print id, f[i] }' DECISIONS.md)
while IFS=: read -r file line text; do
  for id in $(grep -oE 'D-[0-9]+:' <<< "${text#*#}" | tr -d :); do
    case "$known" in *" $id "*) ;; *) bad "${file#./}:$line" "$id is not in DECISIONS.md" ;; esac
  done
done < <(grep -rnE --include='*.sh' --include=release --include='*.yml' --include=markers --include=steps --include=probes \
  --exclude-dir=.git --exclude-dir=dist '#.*D-[0-9]+:' . || true)

[ "$fail" -eq 0 ] && echo "layout ok"
exit "$fail"

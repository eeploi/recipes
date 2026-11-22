#!/usr/bin/env bash
# Runs each probe in ubuntu-26.04/probes twice, as root, as the helper runs it, and fails one that
# exits non-zero, writes to stderr, prints a line that is not "<key> <value>" (key a-z, 0-9, _ and
# -; value printable, no space at its end), prints a secret, or changes /etc, fail2ban or nginx.
# Its --safe gives names only, one per line, nothing on stderr. For CI only.
# Usage: bin/test-probes.sh [--secret TEXT]... [--expect NAME:REGEX]... [--empty-except NAME,...]
#   --secret TEXT            TEXT is in no probe's output, stdout or stderr
#   --expect NAME:REGEX      a line of probe NAME (its file name without NN- and .probe.sh) matches
#   --empty-except NAME,...  every other probe prints nothing: its software is not there
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C

secrets=()
expects=()
empty_except=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --secret) secrets+=("$2"); shift 2 ;;
    --expect) expects+=("$2"); shift 2 ;;
    --empty-except) empty_except=",$2,"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A probe runs as the helper runs a check (recipe-run): from /, with its PATH and a clean environment.
as_helper() { (cd / && exec env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LC_ALL=C TMPDIR=/tmp bash "$@") < /dev/null; }

# A restart changes the main PID. Only these two, and only with systemd running.
state() {
  bin/etc-state.sh
  if [ -d /run/systemd/system ]; then systemctl show -p Id,ActiveState,MainPID fail2ban nginx; fi
}

fail=0
bad() { echo "$1: $2"; fail=1; }
state > "$tmp/before"
while IFS= read -r file || [ -n "$file" ]; do
  case "$file" in '' | '#'*) continue ;; esac
  name=${file##*/}
  name=${name#[0-9][0-9]-}
  name=${name%.probe.sh}
  for run in 1 2; do
    rc=0
    as_helper "$file" > "$tmp/$name.out" 2> "$tmp/$name.err" || rc=$?
    [ "$rc" -eq 0 ] || bad "$file" "exits $rc (run $run)"
    [ ! -s "$tmp/$name.err" ] || { bad "$file" "writes to stderr (run $run):"; cat "$tmp/$name.err"; }
  done
  echo "== $name"
  cat "$tmp/$name.out"
  if grep -vnE '^[a-z][a-z0-9_-]* [[:print:]]*[^[:space:]]$' "$tmp/$name.out"; then bad "$file" "prints the lines above, not <key> <value>"; fi
  for secret in ${secrets[@]+"${secrets[@]}"}; do
    if grep -qF -- "$secret" "$tmp/$name.out" "$tmp/$name.err"; then bad "$file" "prints the secret $secret"; fi
  done
  if [ -n "$empty_except" ] && [[ $empty_except != *",$name,"* ]] && [ -s "$tmp/$name.out" ]; then
    bad "$file" "prints lines without its software"
  fi
  for expect in ${expects[@]+"${expects[@]}"}; do
    [ "${expect%%:*}" = "$name" ] || continue
    grep -qE -- "${expect#*:}" "$tmp/$name.out" || bad "$file" "no line matches ${expect#*:}"
  done
  rc=0
  as_helper "$file" --safe > "$tmp/$name.safe" 2> "$tmp/$name.err" || rc=$?
  [ "$rc" -eq 0 ] || bad "$file" "--safe exits $rc"
  [ ! -s "$tmp/$name.err" ] || bad "$file" "--safe writes to stderr"
  if grep -vnE '^[^[:space:]]+$' "$tmp/$name.safe"; then bad "$file" "--safe prints the lines above, not one name each"; fi
done < ubuntu-26.04/probes
state > "$tmp/after"
diff "$tmp/before" "$tmp/after" || bad probes "changed the server"

# Every --expect names a probe in the list.
for expect in ${expects[@]+"${expects[@]}"}; do
  [ -f "$tmp/${expect%%:*}.out" ] || bad "--expect $expect" "names no probe"
done

[ "$fail" -eq 0 ] && echo "probes ok"
exit "$fail"

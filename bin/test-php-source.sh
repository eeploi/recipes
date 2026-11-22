#!/usr/bin/env bash
# Runs php-source.sh with apt-get, date and sleep stubbed, on a fake clock that sleep and each
# apt-get run move on: sync errors that clear pass after three waits of 60 s; sync errors that last
# stop after ten minutes (eleven tries), as does a slow apt-get (200 s a run, three tries), with the
# message as the last line; another error stops at once, with apt's first error as the last line.
# Each try updates the sury.org source only. As root in a throwaway container, as php-source.sh
# writes /etc/apt. For CI.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
sed 's/{codename}/resolute/g' ubuntu-26.04/php-source.sh > "$tmp/php-source.sh"

# apt-get notes its arguments, takes APT_SECS on the clock, and fails the first FAILS runs with
# ERROR, then apt's closing line.
cat > "$tmp/bin/apt-get" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$T/tries"
echo $(($(cat "$T/clock") + APT_SECS)) > "$T/clock"
[ "$(wc -l < "$T/tries")" -le "$FAILS" ] || exit 0
printf '%s\n' "$ERROR" 'E: Some index files failed to download. They have been ignored, or old ones used instead.'
exit 100
STUB
cat > "$tmp/bin/sleep" <<'STUB'
#!/usr/bin/env bash
echo "$1" >> "$T/sleeps"
echo $(($(cat "$T/clock") + $1)) > "$T/clock"
STUB
cat > "$tmp/bin/date" <<'STUB'
#!/usr/bin/env bash
cat "$T/clock"
STUB
chmod +x "$tmp/bin/"*

sync='E: Failed to fetch https://packages.sury.org/php/dists/resolute/main/binary-amd64/Packages.gz  File has unexpected size (61000 != 62000). Mirror sync in progress? [IP: 192.0.2.10 443]'
other="E: The repository 'https://packages.sury.org/php resolute Release' does not have a Release file."
args='update -q -o Dir::Etc::SourceList=/etc/apt/sources.list.d/sury-php.sources -o Dir::Etc::SourceParts=- -o APT::Get::List-Cleanup=0'

run() {
  rm -f "$tmp/tries" "$tmp/sleeps"
  touch "$tmp/sleeps"
  echo 0 > "$tmp/clock"
  T=$tmp FAILS=$1 APT_SECS=$2 ERROR=$3 PATH="$tmp/bin:$PATH" bash -euo pipefail "$tmp/php-source.sh" 2>&1
}
# tries, waits, and the last line of the output when the run fails.
expect() {
  local tries waits
  tries=$(wc -l < "$tmp/tries")
  waits=$(wc -l < "$tmp/sleeps")
  if [ "$tries" != "$1" ] || [ "$waits" != "$2" ]; then echo "$3: $tries tries and $waits waits, not $1 and $2"; exit 1; fi
  [ "$(sort -u "$tmp/tries")" = "$args" ] || { echo "$3: apt-get ran with other arguments"; exit 1; }
  [ "$waits" = 0 ] || [ "$(sort -u "$tmp/sleeps")" = 60 ] || { echo "$3: a wait not of 60 s"; exit 1; }
}
fails() {
  local out
  if out=$(run "$1" "$2" "$3"); then echo "$out"; echo "$6: php-source.sh passed"; exit 1; fi
  expect "$4" "$5" "$6"
  [ "$(tail -n 1 <<< "$out")" = "$7" ] || { echo "$out"; echo "$6: another last line"; exit 1; }
  echo "ok $6"
}

run 3 1 "$sync" > /dev/null
expect 4 3 'sync errors that clear'
echo 'ok sync errors that clear'
fails 99 1 "$sync" 11 10 'sync errors that last' 'The PHP source is updating; try again later.'
fails 99 200 "$sync" 3 2 'a slow apt-get' 'The PHP source is updating; try again later.'
fails 99 1 "$other" 1 0 'another error' "$other"

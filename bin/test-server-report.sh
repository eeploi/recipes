#!/usr/bin/env bash
# The helper's server-report on a whole server, as eeploi calls it: through sudo as the deploy user,
# after a good recipe-run kept the release's checks and probes. The text report and --json, each
# twice: each exits 0; the JSON parses, eeploi set the server up, every kept check ran and passed,
# every kept probe ran, ok or not-installed, with no line refused; a secret is in no output; /etc,
# fail2ban and nginx are as they were. The text report is left in /root/server-report.txt.
# For CI only, as root, in the server container. Needs jq.
# Usage: bin/test-server-report.sh [--secret TEXT]...
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C

secrets=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --secret) secrets+=("$2"); shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=bin/helper-env.sh
. bin/helper-env.sh

fail=0
bad() { echo "server-report: $*"; fail=1; }
report() { runuser -u deploy -- sudo -n /usr/local/sbin/eeploi-helper server-report "$@"; }

command -v jq > /dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -yq jq > /dev/null
state > "$tmp/before"
for run in 1 2; do
  for form in text json; do
    out=$tmp/$form.$run
    rc=0
    if [ "$form" = json ]; then report --json > "$out" 2> "$out.err" || rc=$?; else report > "$out" 2> "$out.err" || rc=$?; fi
    [ "$rc" -eq 0 ] || { bad "$form, run $run: exit $rc"; cat "$out.err"; }
  done
done
state > "$tmp/after"
diff "$tmp/before" "$tmp/after" || bad "the reports changed /etc, fail2ban or nginx (above)"

for run in 1 2; do
  j=$tmp/json.$run
  jq -e . "$j" > /dev/null || { bad "json, run $run: does not parse"; continue; }
  # Each a list of what is wrong, empty when all is right.
  for test in \
    'if .setup == "eeploi" then empty else "setup \(.setup)" end' \
    'if .checks.state == "ran" then empty else "checks \(.checks.state): \(.checks.reason)" end' \
    'if (.checks.results | length) > 0 then empty else "no checks" end' \
    '.checks.results[] | select(.state != "ok") | "check \(.state) \(.path): \(.notes | join("; "))"' \
    'if .probes.state == "ran" then empty else "probes \(.probes.state): \(.probes.reason)" end' \
    'if (.probes.results | length) > 0 then empty else "no probes" end' \
    '.probes.results[] | select(.state != "ok" and .state != "not-installed") | "probe \(.name) \(.state)"' \
    '.probes.results[] | select(.rejected != 0) | "probe \(.name): \(.rejected) lines refused"'; do
    wrong=$(jq -r "$test" "$j")
    [ -z "$wrong" ] || bad "json, run $run: $wrong"
  done
done

for file in "$tmp"/text.[12] "$tmp"/json.[12]; do
  for secret in ${secrets[@]+"${secrets[@]}"}; do
    if grep -qF -- "$secret" "$file" "$file.err"; then bad "${file##*/}: shows the secret $secret"; fi
  done
done

cp "$tmp/text.2" /root/server-report.txt
cat "$tmp/text.2"
[ "$fail" -eq 0 ] || exit 1
echo 'server-report ok'

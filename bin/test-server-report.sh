#!/usr/bin/env bash
# The helper's server-report on a whole server, as eeploi calls it: through sudo as the deploy user,
# after a good recipe-run kept the release's checks and probes. The text report and --json, each
# twice: each exits 0; the JSON parses, eeploi set the server up, every kept check ran and passed,
# every kept probe ran, ok or not-installed, with no line refused; a secret is in no output; /etc,
# fail2ban and nginx are as they were. The text report is left in /root/server-report.txt.
# For CI only, as root, in the server container. Reads the JSON with python3, which the image has.
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

state > "$tmp/before"
for run in 1 2; do
  for form in text json; do
    out=$tmp/$form.$run
    flag=()
    [ "$form" = text ] || flag=(--json)
    rc=0
    report ${flag[@]+"${flag[@]}"} > "$out" 2> "$out.err" || rc=$?
    [ "$rc" -eq 0 ] || { bad "$form, run $run: exit $rc"; cat "$out.err"; }
  done
done
state > "$tmp/after"
diff "$tmp/before" "$tmp/after" || bad "the reports changed /etc, fail2ban or nginx (above)"

# What is wrong in a JSON report, a line each; nothing when all is right. JSON that doesn't parse,
# or isn't an object, fails.
wrong='
import json, sys
try:
    r = json.load(open(sys.argv[1]))
except ValueError as e:
    sys.exit("does not parse: %s" % e)
if not isinstance(r, dict):
    sys.exit("not a JSON object")
def part(name):
    p = r.get(name)
    return p if isinstance(p, dict) else {}
checks, probes = part("checks"), part("probes")
results = lambda p: p.get("results") if isinstance(p.get("results"), list) else []
if r.get("setup") != "eeploi": print("setup %s" % r.get("setup"))
if checks.get("state") != "ran": print("checks %s: %s" % (checks.get("state"), checks.get("reason")))
if not results(checks): print("no checks")
for c in results(checks):
    if c.get("state") != "ok": print("check %s %s: %s" % (c.get("state"), c.get("path"), "; ".join(c.get("notes") or [])))
if probes.get("state") != "ran": print("probes %s: %s" % (probes.get("state"), probes.get("reason")))
if not results(probes): print("no probes")
for p in results(probes):
    if p.get("state") not in ("ok", "not-installed"): print("probe %s %s" % (p.get("name"), p.get("state")))
    if p.get("rejected") != 0: print("probe %s: %s lines refused" % (p.get("name"), p.get("rejected")))
'
for run in 1 2; do
  if ! out=$(python3 -I -c "$wrong" "$tmp/json.$run" 2>&1); then bad "json, run $run: $out"
  elif [ -n "$out" ]; then while IFS= read -r line; do bad "json, run $run: $line"; done <<< "$out"
  fi
done

for file in "$tmp"/text.[12] "$tmp"/json.[12]; do
  for secret in ${secrets[@]+"${secrets[@]}"}; do
    if grep -qF -- "$secret" "$file" "$file.err"; then bad "${file##*/}: shows the secret $secret"; fi
  done
done

# CI puts it in the job summary.
cp "$tmp/text.2" /root/server-report.txt
[ "$fail" -eq 0 ] || exit 1
echo 'server-report ok'

#!/usr/bin/env bash
# Probe: fail2ban. Whether it runs, and per jail its counts. D-18: counts only, never an address.
# No fail2ban: no lines. README, Probes.
# Lines: running <yes|no>, jail <name> banned <n> total-banned <n> failed <n> total-failed <n>.
set -euo pipefail
# The settings whose values are safe to show (jail.local, jail.d). Not ignoreip: addresses.
safe=(enabled port maxretry findtime bantime bantime.increment bantime.maxtime bantime.factor
  bantime.multipliers backend logpath)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

command -v fail2ban-client > /dev/null || exit 0
if ! fail2ban-client ping > /dev/null 2>&1; then
  echo 'running no'
  exit 0
fi
echo 'running yes'
list=$(fail2ban-client status 2> /dev/null | sed -n 's/.*Jail list:[[:space:]]*//p')
IFS=', ' read -ra jails <<< "$list"
for jail in ${jails[@]+"${jails[@]}"}; do
  [[ $jail =~ ^[A-Za-z0-9_.-]+$ ]] || continue
  status=$(fail2ban-client status "$jail" 2> /dev/null)
  # Each count as a number (+0), so no other text gets through; the list of banned IPs never does.
  awk -v jail="$jail" '/Currently failed:/ { f = $NF } /Total failed:/ { tf = $NF }
    /Currently banned:/ { b = $NF } /Total banned:/ { tb = $NF }
    END { printf "jail %s banned %d total-banned %d failed %d total-failed %d\n", jail, b + 0, tb + 0, f + 0, tf + 0 }' <<< "$status"
done

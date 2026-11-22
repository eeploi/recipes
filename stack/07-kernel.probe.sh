#!/usr/bin/env bash
# Probe: the kernel. The network settings step 7 sets, as the kernel has them now (/proc/sys), and
# whether SCTP, RDS and TIPC can be loaded. README, Probes.
# Lines: sysctl <name> <value>; for a name with *, the values of every interface, comma separated
# when they differ. module <name> <blocked|loadable|not-found> <loaded|not-loaded>, with modprobe.
set -euo pipefail
# The settings whose values are safe to show, as sysctl.d and modprobe.d write them.
safe=('net.ipv4.conf.*.accept_redirects' 'net.ipv6.conf.*.accept_redirects' 'net.ipv4.conf.*.send_redirects'
  net.ipv4.conf.all.log_martians net.ipv4.conf.default.log_martians install blacklist)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

shopt -s nullglob
sysctl() {
  local name=$1 values
  shift
  # An interface that goes away while this runs is skipped.
  values=$(for f in "$@"; do cat "$f" 2> /dev/null || true; done | LC_ALL=C sort -u | paste -sd, -)
  [ -z "$values" ] || echo "sysctl $name $values"
}
sysctl 'net.ipv4.conf.*.accept_redirects' /proc/sys/net/ipv4/conf/*/accept_redirects
sysctl 'net.ipv6.conf.*.accept_redirects' /proc/sys/net/ipv6/conf/*/accept_redirects
sysctl 'net.ipv4.conf.*.send_redirects' /proc/sys/net/ipv4/conf/*/send_redirects
sysctl net.ipv4.conf.all.log_martians /proc/sys/net/ipv4/conf/all/log_martians
sysctl net.ipv4.conf.default.log_martians /proc/sys/net/ipv4/conf/default/log_martians

command -v modprobe > /dev/null || exit 0
for module in sctp rds tipc; do
  if out=$(modprobe -n -v "$module" 2> /dev/null); then
    case "$out" in 'install /bin/false'* | 'install /bin/true'*) can=blocked ;; *) can=loadable ;; esac
  else
    can=not-found
  fi
  if [ -d "/sys/module/$module" ]; then loaded=loaded; else loaded=not-loaded; fi
  echo "module $module $can $loaded"
done

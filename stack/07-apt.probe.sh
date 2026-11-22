#!/usr/bin/env bash
# Probe: apt. The update settings apt reads, after every file (apt-config dump), and the updates
# waiting. No apt: no lines. README, Probes.
# Lines: allowed-origin, origin-pattern, dpkg-option, automatic-reboot, periodic-update-package-lists,
# periodic-unattended-upgrade <value>; updates <n>, security-updates <n>, lists-updated <UTC time>.
set -euo pipefail
# The settings whose values are safe to show, as apt.conf.d writes them.
safe=(Unattended-Upgrade::Allowed-Origins Unattended-Upgrade::Origins-Pattern Unattended-Upgrade::Automatic-Reboot
  DPkg::Options APT::Periodic::Update-Package-Lists APT::Periodic::Unattended-Upgrade)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

command -v apt-config > /dev/null || exit 0
config=$(apt-config dump 2> /dev/null)
# Only these keys: apt's config can hold a proxy's password.
awk 'function value() { v = $0; sub(/^[^ ]+ /, "", v); sub(/;$/, "", v); gsub(/"/, "", v); return v }
  $1 == "Unattended-Upgrade::Allowed-Origins::" { print "allowed-origin " value() }
  $1 == "Unattended-Upgrade::Origins-Pattern::" { print "origin-pattern " value() }
  $1 == "Unattended-Upgrade::Automatic-Reboot" { print "automatic-reboot " value() }
  tolower($1) == "dpkg::options::" { print "dpkg-option " value() }
  $1 == "APT::Periodic::Update-Package-Lists" { print "periodic-update-package-lists " value() }
  $1 == "APT::Periodic::Unattended-Upgrade" { print "periodic-unattended-upgrade " value() }' <<< "$config" \
  | grep -v ' $' || true

# D-20: the updates waiting, from the package lists on the server: a simulated upgrade, no lock
# taken and no cache written.
command -v apt-get > /dev/null || exit 0
sim=$(apt-get -s -o Debug::NoLocking=1 -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache= dist-upgrade 2> /dev/null)
echo "updates $(grep -cE '^Inst [^ ]+ \[' <<< "$sim" || true)"
echo "security-updates $(grep -cE '^Inst [^ ]+ \[.*\(.*-security[ ,]' <<< "$sim" || true)"
stamp=/var/lib/apt/periodic/update-success-stamp
[ ! -f "$stamp" ] || echo "lists-updated $(date -u -r "$stamp" +%Y-%m-%dT%H:%M:%SZ)"

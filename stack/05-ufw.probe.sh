#!/usr/bin/env bash
# Probe: the firewall, UFW. What ufw says it runs with: on or off, the defaults and the rules,
# without their comments. No ufw: no lines. PROBES.md.
# Lines: status <active|inactive>, logging <level>, default <policies>, rule <to> <action> <from>.
set -euo pipefail
# The settings whose values are safe to show (/etc/default/ufw, /etc/ufw/ufw.conf).
safe=(ENABLED LOGLEVEL IPV6 DEFAULT_INPUT_POLICY DEFAULT_OUTPUT_POLICY DEFAULT_FORWARD_POLICY)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

command -v ufw > /dev/null || exit 0
status=$(ufw status verbose 2> /dev/null)
# A rule's comment is free text: never shown.
awk '/^Status: / { print "status " $2; next }
  /^Logging: / { sub(/^Logging: /, ""); print "logging " $0; next }
  /^Default: / { sub(/^Default: /, ""); print "default " $0; next }
  /^--/ { rules = 1; next }
  rules && NF { sub(/[[:space:]]+#.*$/, ""); gsub(/[[:space:]]+/, " "); sub(/ $/, ""); print "rule " $0 }' <<< "$status"

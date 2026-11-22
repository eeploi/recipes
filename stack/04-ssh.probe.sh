#!/usr/bin/env bash
# Probe: SSH. The settings sshd reads, after every drop-in (sshd -T), those in the list only.
# Lines: <setting> <value>, in sshd -T's lower case; hostkey once per key. No sshd: no lines.
# PROBES.md.
set -euo pipefail
# The settings whose values are safe to show. sshd takes them in any case.
safe=(port listenaddress addressfamily permitrootlogin passwordauthentication kbdinteractiveauthentication
  pubkeyauthentication authenticationmethods permitemptypasswords maxauthtries maxsessions logingracetime
  maxstartups allowusers allowgroups denyusers denygroups x11forwarding allowagentforwarding allowtcpforwarding
  allowstreamlocalforwarding gatewayports permittunnel permituserenvironment modulifile kexalgorithms macs
  ciphers hostkeyalgorithms hostkey)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

command -v sshd > /dev/null || exit 0
# D-17: sshd -T reads the config on disk, not the running sshd.
settings=$(sshd -T 2> /dev/null)
awk -v safe=" ${safe[*]} " 'NF > 1 && index(safe, " " $1 " ")' <<< "$settings"

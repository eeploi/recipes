#!/usr/bin/env bash
# Probe: needrestart. Whether the kernel, the CPU microcode or a service waits for a restart, in
# needrestart's batch mode, listing only: it restarts nothing. No needrestart: no lines.
# README, Probes.
# Lines: kernel <current|abi-upgrade|upgrade|unknown>, kernel-running <version>,
# kernel-expected <version>, microcode <current|obsolete|unknown>, service <unit>.
set -euo pipefail
# The settings whose values are safe to show (needrestart's conf.d).
# shellcheck disable=SC2016 # needrestart's names start with $
safe=('$nrconf{restart}' '$nrconf{kernelhints}' '$nrconf{ucodehints}')
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

command -v needrestart > /dev/null || exit 0
out=$(needrestart -b -r l 2> /dev/null) || [ -n "$out" ] || exit 1
awk '$1 == "NEEDRESTART-KCUR:" { print "kernel-running " $2 }
  $1 == "NEEDRESTART-KEXP:" { print "kernel-expected " $2 }
  $1 == "NEEDRESTART-KSTA:" { s = $2 == 1 ? "current" : $2 == 2 ? "abi-upgrade" : $2 == 3 ? "upgrade" : "unknown"; print "kernel " s }
  $1 == "NEEDRESTART-UCSTA:" { s = $2 == 1 ? "current" : $2 == 2 ? "obsolete" : "unknown"; print "microcode " s }
  $1 == "NEEDRESTART-SVC:" && $2 ~ /^[A-Za-z0-9@_.:-]+$/ { print "service " $2 }' <<< "$out"

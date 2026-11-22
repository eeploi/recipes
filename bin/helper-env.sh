# shellcheck shell=bash
# Sourced by the CI scripts that run steps, checks and probes as the helper runs them. For CI only.

# As the helper runs a step, check or probe (recipe-run): from /, with its PATH and a clean environment.
as_helper() { (cd / && exec env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LC_ALL=C TMPDIR=/tmp bash "$@") < /dev/null; }

# What a read-only run must leave as it was: /etc, and fail2ban and nginx, as a restart changes the
# main PID. Only these two: other units, timers among them, change on their own. Without systemd
# running, /etc only.
state() {
  bin/etc-state.sh
  if [ -d /run/systemd/system ]; then systemctl show -p Id,ActiveState,MainPID fail2ban nginx; fi
}

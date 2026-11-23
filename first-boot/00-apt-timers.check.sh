# apt's daily timers stay enabled: the first boot only stops them until the reboot after it.
for timer in apt-daily.timer apt-daily-upgrade.timer; do
  [ "$(systemctl is-enabled "$timer" || true)" = enabled ] || { echo "$timer is not enabled" >&2; exit 1; }
done

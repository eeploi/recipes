# 0. apt's timers stop until the reboot after the first boot, which starts them again; a job of
#    theirs gets ten minutes. apt-get update doesn't wait for the lists lock.
STEP="0. Stop apt's timers"
systemctl stop apt-daily.timer apt-daily-upgrade.timer
APT_WAITED=0
# A running job is activating, a queued one only a job.
while [ -n "$(systemctl list-jobs --no-legend apt-daily.service apt-daily-upgrade.service)" ] \
  || grep -qvxE 'inactive|failed' <<< "$(systemctl is-active apt-daily.service apt-daily-upgrade.service || true)"; do
  [ "$APT_WAITED" -lt 600 ] || { echo "apt's daily jobs still run after ten minutes" >&2; exit 1; }
  sleep 5
  APT_WAITED=$((APT_WAITED + 5))
done

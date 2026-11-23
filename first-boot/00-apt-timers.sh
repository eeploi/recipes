# 0. apt's timers: stopped for the rest of the first boot, and any job of theirs already running
#    gets ten minutes to finish. apt-get update takes the lists lock without waiting (step 0's lock
#    timeout covers dpkg's lock only), so a daily job would fail step 1 or the PHP source. The
#    timers stay enabled: the reboot after the first boot, through the helper, starts them again.
STEP="0. Stop apt's timers"
systemctl stop apt-daily.timer apt-daily-upgrade.timer
APT_WAITED=0
# A running oneshot job is activating, not active.
while grep -qvxE 'inactive|failed' <<< "$(systemctl is-active apt-daily.service apt-daily-upgrade.service || true)"; do
  [ "$APT_WAITED" -lt 600 ] || { echo "apt's daily jobs still run after ten minutes" >&2; exit 1; }
  sleep 5
  APT_WAITED=$((APT_WAITED + 5))
done

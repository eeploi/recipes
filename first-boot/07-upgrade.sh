# 7. Updates: every update Ubuntu offers this server now, once, before the server reports ready.
STEP='7. Install updates'
# D-28: everything waiting, not only security (step 7 limits unattended-upgrades to that later); a
# failed update fails the first boot. After step 7, so an update keeps eeploi's config files. New
# packages an update needs (a new kernel) come in; nothing is removed. Step 1 just updated the lists.
# Step 0 has it wait for dpkg's lock. needrestart waits: a libc update would have it
# restart the cloud-init unit running this script. The reboot after the first boot, through the
# helper, restarts everything.
NEEDRESTART_SUSPEND=1 apt-get upgrade --with-new-pkgs -yq
# An update of apt starts apt's timers again (step 0 stopped them). After an update of systemd,
# systemd re-executes and may take a moment to answer.
APT_TRIES=0
until systemctl stop apt-daily.timer apt-daily-upgrade.timer; do
  APT_TRIES=$((APT_TRIES + 1))
  [ "$APT_TRIES" -lt 12 ] || { echo "apt's timers could not be stopped after the updates" >&2; exit 1; }
  sleep 5
done
echo '# Written by the eeploi recipes once the first boot installed every update Ubuntu offered the server then.' > /etc/eeploi/updated

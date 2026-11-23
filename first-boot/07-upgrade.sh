# 7. Updates: every update Ubuntu offers this server now, once, before the server reports ready.
STEP='7. Install updates'
# D-28: everything waiting, not only security (step 7 limits unattended-upgrades to that later); a
# failed update fails the first boot. After step 7, so an update keeps eeploi's config files. New
# packages an update needs (a new kernel) come in; nothing is removed. Step 1 just updated the lists.
# apt's timers can hold the lock at first boot. needrestart waits: a libc update would have it
# restart the cloud-init unit running this script. The reboot after the first boot, through the
# helper, restarts everything.
NEEDRESTART_SUSPEND=1 apt-get -o DPkg::Lock::Timeout=600 upgrade --with-new-pkgs -yq
echo '# Written by the eeploi recipes once the first boot installed every update Ubuntu offered the server then.' > /etc/eeploi/updated

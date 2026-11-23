# 7. Updates: every update waiting, once, before the server reports ready.
STEP='7. Install updates'
# D-28: everything waiting, not only security (step 7 limits unattended-upgrades to that later); a
# failed update fails the first boot. After step 7, so an update keeps eeploi's config files and
# needrestart restarts what it patched. Step 1 just updated the lists. apt's timers can hold the
# lock at first boot. The reboot comes after the first boot, through the helper.
apt-get -o DPkg::Lock::Timeout=600 full-upgrade -yq
echo '# Written by the eeploi recipes once the first boot installed every update waiting.' > /etc/eeploi/updated

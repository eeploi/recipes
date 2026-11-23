# 7. Updates: a new server installs every update waiting once, before it reports ready. After
#    this, unattended-upgrades takes security updates only (step 7, D-6).
STEP='7. Install updates'
# D-28: everything waiting, not only security, and a failed update fails the first boot. A
# full-upgrade, so updates that need a new package (a new kernel) come in too. It runs after step
# 7, so an update keeps the config files eeploi changed and needrestart restarts what it patched,
# and before step 10 starts the services. Step 1 has just updated the package lists. apt's timers
# can hold the lock at first boot: apt waits up to ten minutes for it. No reboot here: it comes
# after the first boot, through the helper.
apt-get -o DPkg::Lock::Timeout=600 full-upgrade -yq
echo '# Written by the eeploi recipes once the first boot installed every update waiting.' > /etc/eeploi/updated

# apt runs the security updates.
apt-config dump | grep '^APT::Periodic::Unattended-Upgrade "1";' >/dev/null # not -q: under pipefail, grep stopping early fails apt-config
# needrestart is installed and restarts services on its own.
command -v needrestart >/dev/null
grep -rqs "^\$nrconf{restart} = 'a';" /etc/needrestart/conf.d/
# SCTP can't be loaded.
modprobe -n -v sctp | grep 'install /bin/false' >/dev/null
# SCTP is not loaded. If it can't be unloaded, a reboot does.
[ ! -d /sys/module/sctp ]

# apt runs the security updates.
apt-config dump | grep -q '^APT::Periodic::Unattended-Upgrade "1";'
# needrestart is installed and restarts services on its own.
command -v needrestart >/dev/null
grep -rqs "^\$nrconf{restart} = 'a';" /etc/needrestart/conf.d/
# SCTP can't be loaded.
modprobe -n -v sctp | grep -q 'install /bin/false'

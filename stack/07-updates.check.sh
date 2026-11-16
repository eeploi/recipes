# apt runs the security updates.
apt-config dump | grep -q '^APT::Periodic::Unattended-Upgrade "1";'

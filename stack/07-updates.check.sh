# apt runs the security updates.
apt-config dump | grep '^APT::Periodic::Unattended-Upgrade "1";' >/dev/null # not -q: under pipefail, grep stopping early fails apt-config
# needrestart is installed and restarts services on its own.
command -v needrestart >/dev/null
grep -rqs "^\$nrconf{restart} = 'a';" /etc/needrestart/conf.d/
# SCTP, RDS and TIPC can't be loaded, and are not loaded. If one can't be unloaded, a reboot does.
for module in sctp rds tipc; do
  modprobe -n -v "$module" | grep 'install /bin/false' >/dev/null || { echo "$module can be loaded" >&2; exit 1; }
  [ ! -d "/sys/module/$module" ] || { echo "$module is loaded" >&2; exit 1; }
done
# The settings come back at boot: the file has each line.
for setting in 'net.ipv4.conf.*.accept_redirects = 0' 'net.ipv6.conf.*.accept_redirects = 0' \
  'net.ipv4.conf.*.send_redirects = 0' 'net.ipv4.conf.all.log_martians = 1' \
  'net.ipv4.conf.default.log_martians = 1'; do
  grep -qxF "$setting" /etc/sysctl.d/60-eeploi-network.conf || { echo "60-eeploi-network.conf: not $setting" >&2; exit 1; }
done
# No interface takes or sends ICMP redirects; martians are logged. An interface that goes away
# while this runs is skipped.
shopt -s nullglob
for key in /proc/sys/net/ipv4/conf/*/accept_redirects /proc/sys/net/ipv6/conf/*/accept_redirects \
  /proc/sys/net/ipv4/conf/*/send_redirects; do
  read -r value 2>/dev/null < "$key" || continue
  [ "$value" = 0 ] || { echo "$key is not 0" >&2; exit 1; }
done
for key in /proc/sys/net/ipv4/conf/all/log_martians /proc/sys/net/ipv4/conf/default/log_martians; do
  [ "$(cat "$key")" = 1 ] || { echo "$key is not 1" >&2; exit 1; }
done

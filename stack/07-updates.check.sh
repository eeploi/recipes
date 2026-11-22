apt_config=$(apt-config dump)
# apt runs the security updates.
grep -qxF 'APT::Periodic::Unattended-Upgrade "1";' <<< "$apt_config"
# Security updates only (Ubuntu's and Ubuntu Pro's), Ubuntu's own list cleared, and sury.org's exactly when the PHP comes from
# there; no origin pattern.
# shellcheck disable=SC2016 # the ${} is apt's
origins='Unattended-Upgrade::Allowed-Origins:: "${distro_id}:${distro_codename}-security";
Unattended-Upgrade::Allowed-Origins:: "${distro_id}ESMApps:${distro_codename}-apps-security";
Unattended-Upgrade::Allowed-Origins:: "${distro_id}ESM:${distro_codename}-infra-security";'
# shellcheck disable=SC2016 # the ${} is apt's
[ ! -f /etc/apt/sources.list.d/sury-php.sources ] || origins+=$'\n''Unattended-Upgrade::Allowed-Origins:: "deb.sury.org:${distro_codename}";'
[ "$(grep '^Unattended-Upgrade::Allowed-Origins:: ' <<< "$apt_config")" = "$origins" ] \
  || { echo 'unattended-upgrades: not the origins eeploi sets' >&2; exit 1; }
if grep '^Unattended-Upgrade::Origins-Pattern:: ' <<< "$apt_config" >/dev/null; then
  echo 'unattended-upgrades: an origin pattern is set' >&2; exit 1
fi
# A package update keeps the config files eeploi changed.
for option in --force-confdef --force-confold; do
  grep -ixF "DPkg::Options:: \"$option\";" <<< "$apt_config" >/dev/null || { echo "dpkg: not $option" >&2; exit 1; }
done
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

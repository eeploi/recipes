# 7. Security updates only, services restarted after one, SCTP, RDS and TIPC blocked, no ICMP
# redirects
STEP='7. Security updates only'
cat > /etc/apt/apt.conf.d/52eeploi-unattended <<'APT'
Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };
Unattended-Upgrade::Automatic-Reboot "false";
APT
printf 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
' > /etc/apt/apt.conf.d/20auto-upgrades
# needrestart restarts the services a security update patched on its own: a reload would leave an
# old nginx binary running.
mkdir -p /etc/needrestart/conf.d
# shellcheck disable=SC2016 # the $ is meant literally
printf '$nrconf{restart} = '"'a'"';\n' > /etc/needrestart/conf.d/50-eeploi.conf
# Nothing eeploi runs uses SCTP, RDS or TIPC. The local- prefix keeps these apart from Ubuntu's own
# disable-<module>.conf files in kmod. DCCP left the kernel in 6.16.
for module in sctp rds tipc; do
  printf 'install %s /bin/false\n' "$module" > "/etc/modprobe.d/local-disable-$module.conf"
  # A server that already has it loaded drops it now; if it is in use, a reboot does.
  modprobe -r "$module" 2>/dev/null || true
done
# No interface takes or sends ICMP redirects: a server is no router, and a redirect could move its
# traffic. Martians (packets from an address that can't be) are logged. Only what Ubuntu doesn't set
# already; no IPv6 router advertisement lines, some providers route IPv6 by them. The * takes every
# interface, also one that comes later. systemd-sysctl, which reads the file at boot, applies it now.
printf '%s\n' 'net.ipv4.conf.*.accept_redirects = 0' 'net.ipv6.conf.*.accept_redirects = 0' \
  'net.ipv4.conf.*.send_redirects = 0' 'net.ipv4.conf.all.log_martians = 1' \
  'net.ipv4.conf.default.log_martians = 1' > /etc/sysctl.d/60-eeploi-network.conf
/usr/lib/systemd/systemd-sysctl /etc/sysctl.d/60-eeploi-network.conf

# 7. Security updates only, services restarted after one, SCTP blocked
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
printf '$nrconf{restart} = '"'a'"';\n' > /etc/needrestart/conf.d/50-eeploi.conf
# Nothing eeploi runs uses SCTP. The local- prefix keeps this apart from Ubuntu's own
# disable-<module>.conf files in kmod.
printf 'install sctp /bin/false\n' > /etc/modprobe.d/local-disable-sctp.conf
# A server that already has SCTP loaded drops it now; if it is in use, a reboot does.
modprobe -r sctp 2>/dev/null || true

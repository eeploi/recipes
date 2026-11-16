# 7. Security updates only, alert file when a reboot is needed
STEP='7. Security updates only'
cat > /etc/apt/apt.conf.d/52eeploi-unattended <<'APT'
Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };
Unattended-Upgrade::Automatic-Reboot "false";
APT
printf 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
' > /etc/apt/apt.conf.d/20auto-upgrades

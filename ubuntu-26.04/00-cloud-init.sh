# 0. cloud-init after AppArmor: on Ubuntu 26.04, cloud-init-local can start before AppArmor is
#    loaded, and then races the rename of the network card (such as enp1s0 to eth0) during its
#    DHCP. cloud-init's boot stages then fail, though the network comes up. Seen since
#    open-vm-tools 2:13.0.10-1ubuntu1.1, which dropped the delay that had it start after
#    apparmor.service. canonical/cloud-init#7142, closed upstream without a fix.
#    D-29: this orders it after apparmor.service again; remove once cloud-init fixes the race.
STEP='0. cloud-init after AppArmor'
dropin_dir=/etc/systemd/system/cloud-init-local.service.d
install -d -m 755 "$dropin_dir"
printf '%s\n' '[Unit]' 'After=apparmor.service' > "$dropin_dir/10-after-apparmor.conf"
chown root:root "$dropin_dir/10-after-apparmor.conf"
chmod 644 "$dropin_dir/10-after-apparmor.conf"
systemctl daemon-reload

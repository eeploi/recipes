# 0. cloud-init after AppArmor: on Ubuntu 26.04, cloud-init-local otherwise races the rename of the
#    network card during its DHCP, and cloud-init's boot stages fail (canonical/cloud-init#7210).
#    D-29: a workaround; remove once cloud-init fixes the race.
STEP='0. cloud-init after AppArmor'
printf '%s\n' '[Unit]' 'After=apparmor.service' \
  | install -D -m 644 /dev/stdin /etc/systemd/system/cloud-init-local.service.d/10-after-apparmor.conf
systemctl daemon-reload

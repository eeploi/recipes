# fail2ban accepts its config.
fail2ban-client -t >/dev/null
# No old jail left aside.
[ ! -e /etc/fail2ban/jail.d/eeploi.conf.prev ]
# A running fail2ban has loaded eeploi's jail: its bantime, not the default 10 minutes.
if systemctl is-active --quiet fail2ban; then [ "$(fail2ban-client get sshd bantime)" = 3600 ]; fi

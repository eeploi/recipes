# fail2ban accepts its config.
fail2ban-client -t >/dev/null
# No old jail left aside.
[ ! -e /etc/fail2ban/jail.d/eeploi.conf.prev ]
# A running fail2ban has loaded eeploi's jail: its bantime, not the default 10 minutes.
if systemctl is-active --quiet fail2ban; then [ "$(fail2ban-client get sshd bantime)" = 3600 ]; fi
# Repeat offenders stay out longer: bans that grow up to a week, and the recidive jail, which a
# running fail2ban runs.
grep -qxF 'bantime.increment = true' /etc/fail2ban/jail.d/eeploi.conf
grep -qxF 'bantime.maxtime = 1w' /etc/fail2ban/jail.d/eeploi.conf
grep -qxF '[recidive]' /etc/fail2ban/jail.d/eeploi.conf
if systemctl is-active --quiet fail2ban; then fail2ban-client status recidive >/dev/null; fi
# The jail watches this server's SSH port, and no other.
[ "$(grep '^port' /etc/fail2ban/jail.d/eeploi.conf)" = "port = $SSH_PORT" ]

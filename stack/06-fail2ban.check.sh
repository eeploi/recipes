# fail2ban accepts its config.
fail2ban-client -t >/dev/null
# No old jail left aside.
[ ! -e /etc/fail2ban/jail.d/eeploi.conf.prev ]
# A running fail2ban has loaded eeploi's jail: its bantime, not the default 10 minutes.
if systemctl is-active --quiet fail2ban; then [ "$(fail2ban-client get sshd bantime)" = 3600 ]; fi
# The jail watches this server's SSH port, and no other.
[ "$(grep '^port' /etc/fail2ban/jail.d/eeploi.conf)" = "port = $SSH_PORT" ]
# The jail file is the one step 6 writes, line for line: the sshd jail with bans that grow, and the
# recidive jail with its values.
[ "$(cat /etc/fail2ban/jail.d/eeploi.conf)" = "$(printf '[sshd]\nenabled = true\nport = %s\nmaxretry = 5\nbantime = 1h\nbantime.increment = true\nbantime.maxtime = 1w\n\n[recidive]\nenabled = true\nbantime = 1w\nfindtime = 1d\nmaxretry = 5' "$SSH_PORT")" ] \
  || { echo "eeploi's jail is not the one step 6 writes" >&2; exit 1; }
# A running fail2ban runs the recidive jail, on fail2ban's own log.
if systemctl is-active --quiet fail2ban; then
  fail2ban-client status recidive >/dev/null
  fail2ban-client get recidive logpath | grep -qF /var/log/fail2ban.log
fi

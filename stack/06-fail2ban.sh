# 6. fail2ban for SSH on the custom port
STEP='6. fail2ban for SSH on the custom port'
jail=/etc/fail2ban/jail.d/eeploi.conf
# The old jail stays aside until fail2ban accepts the new one, and comes back if it doesn't.
rm -f "$jail.prev"
[ ! -f "$jail" ] || cp -a "$jail" "$jail.prev"
cat > "$jail" <<JAIL
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 5
bantime = 1h
JAIL
if ! fail2ban-client -t; then
  if [ -f "$jail.prev" ]; then mv -f "$jail.prev" "$jail"; else rm -f "$jail"; fi
  echo 'fail2ban refuses its config, the jail is as it was' >&2
  exit 1
fi
rm -f "$jail.prev"
# A live server takes the jail now; a stopped fail2ban stays stopped.
systemctl try-reload-or-restart fail2ban

# 6. fail2ban for SSH on the custom port
STEP='6. fail2ban for SSH on the custom port'
cat > /etc/fail2ban/jail.d/eeploi.conf <<JAIL
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 5
bantime = 1h
JAIL
# A live server takes the jail now, once fail2ban accepts it; a stopped fail2ban stays stopped.
fail2ban-client -t >/dev/null
systemctl try-reload-or-restart fail2ban

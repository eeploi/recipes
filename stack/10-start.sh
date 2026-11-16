# 10. Start everything
STEP='10. Start everything'
systemctl daemon-reload
systemctl enable --now nginx php$PHP-fpm supervisor fail2ban unattended-upgrades
# Each site gets a Redis of its own from this package (eeploi-redis@<user>); the shared one would
# listen where every user on the server reaches it.
systemctl disable --now redis-server
systemctl reload nginx
systemctl restart php$PHP-fpm fail2ban
systemctl restart ssh.socket ssh

# eeploi logs in over IPv4: the new port must listen there too, or this step fails and says so.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  ss -Hltn "sport = :$SSH_PORT" | grep -q '0\.0\.0\.0:' && break
  sleep 1
done
ss -Hltn "sport = :$SSH_PORT" | grep -q '0\.0\.0\.0:' || { echo "SSH port $SSH_PORT does not listen on IPv4: $(ss -Hltn "sport = :$SSH_PORT" | awk '{print $4}' | paste -sd ' ' -)" >&2; exit 1; }

echo "Provisioned {name}. SSH: $DEPLOY_USER@<host> -p $SSH_PORT"
[ "$SSH_PORT" = 22 ] || echo "Test the new port in a second terminal, then: sudo {helper_path} firewall-close-22"

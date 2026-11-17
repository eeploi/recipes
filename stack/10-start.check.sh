# The services run, the shared Redis doesn't, and SSH listens on IPv4.
systemctl is-active --quiet nginx "php$PHP-fpm" supervisor fail2ban ssh
if systemctl is-active --quiet redis-server; then echo 'The shared redis-server runs' >&2; exit 1; fi
ss -Hltn "sport = :$SSH_PORT" | grep -q '0\.0\.0\.0:'

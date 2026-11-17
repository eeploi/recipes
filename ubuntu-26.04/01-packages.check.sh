# Every program a site needs is installed.
for program in nginx "php$PHP" "php-fpm$PHP" redis-server supervisord node npm composer ufw fail2ban-client minisign; do
  command -v "$program" >/dev/null || { echo "$program is missing" >&2; exit 1; }
done

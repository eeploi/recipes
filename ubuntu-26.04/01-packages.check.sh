# Every program a site needs is installed. Composer and the pinned npm by their path in /usr/local/bin:
# the helper runs checks with PATH=/usr/sbin:/usr/bin:/sbin:/bin, where command -v finds neither.
for program in nginx "php$PHP" "php-fpm$PHP" redis-server supervisord node npm ufw fail2ban-client minisign; do
  command -v "$program" >/dev/null || { echo "$program is missing" >&2; exit 1; }
done
for program in /usr/local/bin/composer /usr/local/bin/npm; do
  [ -x "$program" ] || { echo "$program is missing" >&2; exit 1; }
done

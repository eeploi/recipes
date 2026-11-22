# The deploy user exists, has no password and has eeploi's key; only root and it may use cron and at.
id "$DEPLOY_USER" >/dev/null
passwd -S "$DEPLOY_USER" | awk '{ print $2 }' | grep -qx L
[ -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ]
[ "$(cat /etc/cron.allow)" = "$(printf 'root\n%s' "$DEPLOY_USER")" ]
cmp -s /etc/cron.allow /etc/at.allow
# PHP-FPM's stock [www] pool, as FPM reads it after every file: on demand, two workers at most, a
# socket only root may open.
fpm=$("php-fpm$PHP" -tt 2>&1) || { echo "php-fpm$PHP -tt fails" >&2; exit 1; }
www=$(awk '/NOTICE: \[/ { in_www = /NOTICE: \[www\]$/; next } in_www { sub(/.*NOTICE:[[:space:]]*/, ""); print }' <<< "$fpm")
for setting in 'pm = ondemand' 'pm.max_children = 2' 'listen.owner = root' 'listen.group = root' 'listen.mode = 0600'; do
  grep -qxF "$setting" <<< "$www" || { echo "php-fpm [www]: not $setting" >&2; exit 1; }
done
# PHP-FPM sends no X-Powered-By header and keeps no upload progress in the session: the values PHP
# reads from FPM's own php.ini and conf.d, after every ini file. A setting PHP doesn't know fails.
# shellcheck disable=SC2016 # the $ is PHP's
fpm_ini() { PHP_INI_SCAN_DIR=/etc/php/$PHP/fpm/conf.d "php$PHP" -c "/etc/php/$PHP/fpm/php.ini" \
  -r '$v = ini_get($argv[1]); echo $v === false ? "unknown" : ($v ? "on" : "off");' -- "$1"; }
for key in expose_php session.upload_progress.enabled; do
  [ "$(fpm_ini "$key")" = off ] || { echo "php-fpm: $key is not off" >&2; exit 1; }
done

# 2. Deploy user, SSH key only; PHP-FPM's stock pool closed, no PHP version in a header
STEP='2. Deploy user'
{deploy_user}
# Each site runs as its own user, in a PHP-FPM pool of its own (eeploi-helper php-pool-write). FPM
# needs one pool to start: [www] stays www-data's, on demand, so it holds no processes, two at most,
# and nothing reaches it: its socket is root's, 0600 (nginx runs as www-data).
sed -i -e 's/^pm = .*/pm = ondemand/' -e 's/^pm\.max_children = .*/pm.max_children = 2/' \
  -e 's/^;\?listen\.owner = .*/listen.owner = root/' -e 's/^;\?listen\.group = .*/listen.group = root/' \
  -e 's/^;\?listen\.mode = .*/listen.mode = 0600/' /etc/php/$PHP/fpm/pool.d/www.conf
# No X-Powered-By header with the PHP version, and no upload progress in the session: Laravel
# doesn't use it, and PHP advises it off for CVE-2026-115560. A file of its own: eeploi-helper
# rewrites 90-eeploi.ini.
printf '; Written by eeploi at first boot.\nexpose_php = Off\nsession.upload_progress.enabled = 0\n' > /etc/php/$PHP/fpm/conf.d/80-eeploi-server.ini
# The pools share one OPcache: a site runs another's cached script only if it may read the file.
printf '; Written by eeploi at first boot; eeploi-helper (php-pool-write) keeps it.\nopcache.validate_permission = 1\n' > /etc/php/$PHP/fpm/conf.d/90-eeploi.ini
# Only root and the deploy user get a crontab or an at job: a site's schedule goes through eeploi
# into /etc/cron.d, so a hacked site can't plant a job of its own to stay in.
printf 'root\n%s\n' "$DEPLOY_USER" | tee /etc/cron.allow > /etc/at.allow
chmod 644 /etc/cron.allow /etc/at.allow

# 2. Deploy user, SSH key only
STEP='2. Deploy user'
{deploy_user}
# Each site runs as its own user, in a PHP-FPM pool of its own (eeploi-helper php-pool-write). FPM
# needs one pool to start: [www] stays www-data's, on demand, so it holds no processes.
sed -i "s/^pm = .*/pm = ondemand/" /etc/php/$PHP/fpm/pool.d/www.conf
# The pools share one OPcache: a site runs another's cached script only if it may read the file.
printf '; Written by eeploi at first boot; eeploi-helper (php-pool-write) keeps it.\nopcache.validate_permission = 1\n' > /etc/php/$PHP/fpm/conf.d/90-eeploi.ini
# Only root and the deploy user get a crontab or an at job: a site's schedule goes through eeploi
# into /etc/cron.d, so a hacked site can't plant a job of its own to stay in.
printf 'root\n%s\n' "$DEPLOY_USER" | tee /etc/cron.allow > /etc/at.allow
chmod 644 /etc/cron.allow /etc/at.allow

# Every program a site needs is installed. Composer and the pinned npm by their path in /usr/local/bin:
# the helper runs checks with PATH=/usr/sbin:/usr/bin:/sbin:/bin, where command -v finds neither.
for program in nginx "php$PHP" "php-fpm$PHP" redis-server supervisord node ufw fail2ban-client minisign; do
  command -v "$program" >/dev/null || { echo "$program is missing" >&2; exit 1; }
done
for program in /usr/local/bin/composer /usr/local/bin/npm; do
  [ -x "$program" ] || { echo "$program is missing" >&2; exit 1; }
done
# The pinned npm's builtin config has no globalignorefile, and turns the update notice off, once.
[ "$(grep -E '^[[:space:]]*(globalignorefile|update-notifier)[[:space:]]*=' /usr/local/lib/node_modules/npm/npmrc)" = 'update-notifier=false' ]
# Another PHP than Ubuntu's comes from packages.sury.org: apt checks it with the key php-source.sh
# pins (15058500A0235D97F5D10063B188E2B695BD4743), byte for byte, and the source is that one. The
# Launchpad PPA's source and key are gone.
if compgen -G '/etc/apt/sources.list.d/ondrej-ubuntu-php-*' >/dev/null || [ -e /etc/apt/keyrings/ondrej.asc ]; then
  echo 'the Launchpad PPA is still a source' >&2; exit 1
fi
if [ -e /etc/apt/sources.list.d/sury-php.sources ]; then
  [ "$(sha256sum < /etc/apt/keyrings/sury-php.asc)" = '8d2fc1d4a291afb9f7e4cb2b6f263a73ca74107bc40bf5cfd6346acc31506f3d  -' ]
  [ "$(cat /etc/apt/sources.list.d/sury-php.sources)" = "$(printf 'Types: deb\nURIs: https://packages.sury.org/php\nSuites: %s\nComponents: main\nSigned-By: /etc/apt/keyrings/sury-php.asc' "$VERSION_CODENAME")" ]
fi

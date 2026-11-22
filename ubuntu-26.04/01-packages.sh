# 1. Packages: nginx, PHP and Node from Ubuntu's own archive, a pinned npm on top. Only another
#    PHP version than Ubuntu's adds packages.sury.org, as a fixed source with a pinned key.
STEP='1. Packages'
# D-5: Ubuntu's PHP, or another one from packages.sury.org.
# The Launchpad PPA an older release added has no builds for new Ubuntu releases: its source and
# key go, whatever the PHP.
rm -f /etc/apt/keyrings/ondrej.asc /etc/apt/trusted.gpg.d/ondrej-ubuntu-php.gpg /etc/apt/trusted.gpg.d/ondrej-ubuntu-php.gpg~ \
  /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list /etc/apt/sources.list.d/ondrej-ubuntu-php-*.sources
apt-get update -q
apt-get install -yq curl gnupg ca-certificates unzip git ufw fail2ban unattended-upgrades needrestart acl minisign
{php_source}
apt-get install -yq nginx redis-server supervisor nodejs npm {database} \
  php$PHP-fpm php$PHP-cli php$PHP-common php$PHP-curl php$PHP-mbstring php$PHP-xml php$PHP-zip \
  php$PHP-bcmath php$PHP-intl php$PHP-gd php$PHP-redis php$PHP-mysql php$PHP-pgsql php$PHP-sqlite3
npm install -g --no-audit --no-fund --fetch-retries=5 npm@{npm}
# The pinned npm takes over Ubuntu's builtin config: without globalignorefile, which npm warns about
# on every run, and without the update notice, as eeploi pins npm. Written whole, so a run again
# gives the same file.
NPMRC=/usr/local/lib/node_modules/npm/npmrc
NPMRC_TMP=$(mktemp "$NPMRC.XXXXXX")
{ [ ! -f "$NPMRC" ] || grep -vE '^[[:space:]]*(globalignorefile|update-notifier)[[:space:]]*=' "$NPMRC" || true; echo 'update-notifier=false'; } > "$NPMRC_TMP"
chmod 644 "$NPMRC_TMP"
mv -f "$NPMRC_TMP" "$NPMRC"
[ -x /usr/local/bin/composer ] || curl -fsSL --retry 5 --retry-all-errors https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

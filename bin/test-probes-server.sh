#!/usr/bin/env bash
# The probes on a whole server, as CI builds one, with secrets planted where a probe reads: in an
# nginx server block (in a quoted ; and a comment too, and in a file after one whose } # and quote
# inside a word would put a reading out of step with nginx's), a PHP-FPM pool and ini file, apt's config,
# SSH's, MariaDB's and a UFW rule's comment; Redis with a password, an IP banned, and eeploi's
# addresses in fail2ban's ignore list. With a sury.org
# PHP, PostgreSQL too, its password in a conf.d file: not with Ubuntu's PHP, whose server the
# ssh-audit and Lynis reports read after this. bin/test-probes.sh must pass, with none of
# them in the output and the lines expected. Then a probe with a line more that prints a secret,
# writes to /etc, or writes to stderr must fail it. The server is as it was after, also on a failure.
# For CI only, as root, in the server container.
set -euo pipefail
cd "$(dirname "$0")/.."

php=$(sed -n 's/^PHP=//p' /etc/eeploi/recipes.conf)
www=/etc/php/$php/fpm/pool.d/www.conf
planted=()
plant() { planted+=("$1"); cat > "$1"; }
restore() {
  rm -f ${planted[@]+"${planted[@]}"} /etc/written
  [ ! -f /root/www.conf ] || cp /root/www.conf "$www"
  if [ -f /root/redis.conf ]; then cp /root/redis.conf /etc/redis/redis.conf; systemctl restart redis-server; fi
  rm -f /root/www.conf /root/redis.conf
  [ -z "${copy:-}" ] || rm -rf "$copy"
  ufw delete allow 8082/tcp > /dev/null || true
  fail2ban-client set sshd unbanip 203.0.113.7 > /dev/null || true
}
trap restore EXIT

if [ "$php" != 8.5 ]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -yq postgresql > /dev/null
  for d in /etc/postgresql/*/main/conf.d; do
    echo "primary_conninfo = 'host=db.example password=PLANTED-pg'" | plant "$d/99-planted.conf"
  done
fi
plant /etc/nginx/conf.d/planted.conf <<'NGINX'
server {
    listen 8081;
    server_name planted.example;
    add_header X-Planted "a; listen PLANTED-nginx-quote";
    fastcgi_param APP_KEY PLANTED-nginx-param; # listen PLANTED-nginx-comment
    add_header X-A}# "
    server_tokens "
    ;
}
NGINX
plant /etc/nginx/conf.d/zz-planted.conf <<'NGINX'
server {
    listen 8083;
    location / { fastcgi_param DB_PASSWORD PLANTED-nginx-later; }
}
NGINX
nginx -t 2> /dev/null
cp "$www" /root/www.conf
printf 'env[DB_PASSWORD] = PLANTED-fpm-env\nphp_admin_value[mysqli.default_pw] = PLANTED-fpm-admin\n' >> "$www"
echo 'mysqli.default_pw = PLANTED-php-ini' | plant "/etc/php/$php/fpm/conf.d/99-planted.ini"
echo 'Acquire::http::Proxy "http://user:PLANTED-apt@proxy.example:3128";' | plant /etc/apt/apt.conf.d/99planted
echo 'Banner /etc/ssh/PLANTED-ssh' | plant /etc/ssh/sshd_config.d/99-planted.conf
printf '[mysqld]\nplanted-option = PLANTED-mysql\n' | plant /etc/mysql/mariadb.conf.d/99-planted.cnf
ufw allow 8082/tcp comment PLANTED-ufw > /dev/null
cp /etc/redis/redis.conf /root/redis.conf
echo 'requirepass PLANTED-redis' >> /etc/redis/redis.conf
systemctl restart redis-server
fail2ban-client set sshd banip 203.0.113.7 > /dev/null

composer=$(COMPOSER_ALLOW_SUPERUSER=1 composer --version --no-plugins --no-interaction 2> /dev/null | awk '{ print $3; exit }')
npm=$(grep -o 'npm@[0-9.]*$' /root/by-hand.sh)
# eeploi's addresses (bin/render.sh), in the ignore list of every jail, never show either.
args=(--secret PLANTED --secret 203.0.113.7 --secret 203.0.113.10 --secret 2001:db8::10)
# shellcheck disable=SC2016 # the ${} is apt's
for expect in 'ssh:^port 10022$' 'ssh:^permitrootlogin no$' 'ssh:^passwordauthentication no$' 'ssh:^allowusers deploy$' \
  'ufw:^status active$' 'ufw:^rule 10022/tcp ALLOW IN Anywhere$' 'ufw:^rule 8082/tcp ALLOW IN Anywhere$' \
  'fail2ban:^running yes$' 'fail2ban:^jail sshd banned 1 total-banned 1 ' 'fail2ban:^jail recidive banned ' \
  'apt:^dpkg-option --force-confold$' 'apt:^allowed-origin [$][{]distro_id[}]:[$][{]distro_codename[}]-security$' \
  'apt:^updates [0-9]+$' 'apt:^security-updates [0-9]+$' \
  'kernel:^module sctp blocked not-loaded$' 'kernel:^sysctl net[.]ipv4[.]conf[.][*][.]send_redirects 0$' \
  'nginx:^server [0-9]+ ssl_reject_handshake on$' 'nginx:^server [0-9]+ listen 443 ssl default_server$' \
  'nginx:^server [0-9]+ server_name planted[.]example$' 'nginx:^server [0-9]+ listen 8081$' 'nginx:^server [0-9]+ listen 8083$' \
  'nginx:^http fastcgi_buffer_size 32k$' 'nginx:^http real_ip_header CF-Connecting-IP$' \
  "php-fpm:^pool $php www pm[.]max_children 2\$" "php-fpm:^pool $php www listen[.]mode 0600\$" \
  "php-fpm:^ini $php expose_php Off\$" "php-fpm:^ini $php opcache[.]validate_permission On\$" \
  'mysql:^option bind-address 127[.]0[.]0[.]1$' 'redis:^listen 127[.]0[.]0[.]1:6379$' 'redis:^password yes$' \
  'versions:^package nginx ' "versions:^package php$php-fpm " 'versions:^package mariadb-server ' \
  "versions:^npm ${npm#npm@}\$" "versions:^composer $composer\$"; do
  args+=(--expect "$expect")
done
[ "$php" = 8.5 ] || args+=(--expect 'postgresql:^cluster [0-9]+/main port 5432$' --expect 'postgresql:^cluster [0-9]+/main listen_addresses localhost$')
bin/test-probes.sh "${args[@]}"

copy=$(mktemp -d)
cp -a . "$copy/recipes"
for line in 'echo leak PLANTED-x' 'touch /etc/written' 'echo oops >&2'; do
  cp stack/04-ssh.probe.sh "$copy/recipes/stack/"
  echo "$line" >> "$copy/recipes/stack/04-ssh.probe.sh"
  if out=$("$copy/recipes/bin/test-probes.sh" --secret PLANTED); then echo "$out"; echo "a probe with $line passed"; exit 1; fi
  rm -f /etc/written
done
echo 'probes on the server ok'

# The catch-all for unknown hosts is on, the default server for 443 on IPv4 and IPv6, refuses the
# TLS handshake, and has no certificate of its own, nor the one an older release made.
[ "$(readlink /etc/nginx/sites-enabled/catch-all)" = /etc/nginx/sites-available/catch-all ] || { echo 'the catch-all is off' >&2; exit 1; }
grep -qx '    listen 443 ssl default_server;' /etc/nginx/sites-available/catch-all || { echo 'the catch-all is not the IPv4 default' >&2; exit 1; }
grep -qxF '    listen [::]:443 ssl default_server;' /etc/nginx/sites-available/catch-all || { echo 'the catch-all is not the IPv6 default' >&2; exit 1; }
grep -qx '    ssl_reject_handshake on;' /etc/nginx/sites-available/catch-all || { echo 'the catch-all does not refuse the handshake' >&2; exit 1; }
if grep -q 'ssl_certificate' /etc/nginx/sites-available/catch-all || [ -e /etc/nginx/ssl/catch-all.key ] || [ -e /etc/nginx/ssl/catch-all.crt ]; then
  echo 'the catch-all still has a certificate' >&2; exit 1
fi
[ -d /etc/nginx/ssl ]
# No old config left aside: a run that was cut off leaves one.
[ ! -e /etc/nginx/eeploi.prev ] || { echo 'an old nginx config is left aside (/etc/nginx/eeploi.prev)' >&2; exit 1; }
# No nginx version in a header or an error page: nginx.conf turns server_tokens off, and no file
# nginx reads turns it on again (on or build), in any block. Comments don't count.
# D-27: the line is in Ubuntu's nginx.conf, which an nginx update keeps.
grep -qE '^[[:space:]]*server_tokens off;' /etc/nginx/nginx.conf || { echo 'nginx.conf does not turn server_tokens off' >&2; exit 1; }
# nginx -t below fails when nginx can't read its config.
config=$(nginx -T 2> /dev/null | sed 's/#.*//') || true
if grep -qE "(^|[;{}])[[:space:]]*server_tokens[[:space:]]+[\"']?(on|build)[\"']?[[:space:]]*;" <<< "$config"; then
  echo 'nginx turns server_tokens on again' >&2; exit 1
fi
# nginx accepts its config. D-11: nginx -t reads the config on disk.
nginx -t

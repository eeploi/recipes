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
# nginx accepts its config.
nginx -t

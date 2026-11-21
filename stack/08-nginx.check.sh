# nginx accepts its config.
nginx -t
# The catch-all for unknown hosts is on, refuses the TLS handshake, and has no certificate of its own.
[ "$(readlink /etc/nginx/sites-enabled/catch-all)" = /etc/nginx/sites-available/catch-all ]
grep -qx '    ssl_reject_handshake on;' /etc/nginx/sites-available/catch-all
if grep -q 'ssl_certificate' /etc/nginx/sites-available/catch-all || [ -e /etc/nginx/ssl/catch-all.key ]; then
  echo 'the catch-all still has a certificate' >&2; exit 1
fi

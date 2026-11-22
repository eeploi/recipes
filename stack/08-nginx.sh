# 8. nginx: no version in its headers and error pages, room for large headers, no default site, a
#    catch-all that refuses the TLS handshake for unknown hosts; the old config comes back when nginx
#    refuses the new one or doesn't reload
STEP='8. nginx'
# The files this step changes stay aside until nginx takes the new config, and come back if it
# doesn't: a live server keeps serving its sites. A copy left aside by a run that was cut off is the
# old config, so it stays. Every file this step writes or removes is in nginx_files.
nginx_files='/etc/nginx/nginx.conf /etc/nginx/conf.d/eeploi-fastcgi.conf /etc/nginx/sites-enabled/default
/etc/nginx/sites-available/catch-all /etc/nginx/sites-enabled/catch-all /etc/nginx/ssl/catch-all.crt
/etc/nginx/ssl/catch-all.key'
nginx_prev=/etc/nginx/eeploi.prev
nginx_present() { [ -e "$1" ] || [ -L "$1" ]; }
if [ ! -d "$nginx_prev" ]; then
  rm -rf "$nginx_prev.new"
  mkdir "$nginx_prev.new"
  for f in $nginx_files; do
    ! nginx_present "$f" || cp -a --parents "$f" "$nginx_prev.new"
  done
  mv "$nginx_prev.new" "$nginx_prev"
fi
# A copy left aside by an older release has no nginx.conf, which that release never changed: the one
# here is the old one. Without it, a restore would remove nginx.conf.
if [ ! -e "$nginx_prev/etc/nginx/nginx.conf" ]; then
  mkdir -p "$nginx_prev/etc/nginx"
  cp -a /etc/nginx/nginx.conf "$nginx_prev/etc/nginx/nginx.conf.new"
  mv "$nginx_prev/etc/nginx/nginx.conf.new" "$nginx_prev/etc/nginx/nginx.conf"
fi
nginx_restore() {
  for f in $nginx_files; do
    rm -f "$f"
    ! nginx_present "$nginx_prev$f" || cp -a "$nginx_prev$f" "$f"
  done
  rm -rf "$nginx_prev"
}
# The old config back, taken by a running nginx again, and the step fails.
# D-14: another failure in between restores on the next run.
nginx_refused() {
  nginx_restore
  systemctl try-reload-or-restart nginx || true
  echo "$1" >&2
  exit 1
}
# No nginx version or build name in the Server header and on error pages. Ubuntu's nginx.conf sets
# server_tokens in http {}, and a second one in conf.d makes nginx refuse its config, so its own line
# changes, or one comes in at the top of http {} where it has none. D-27: an nginx update keeps this
# nginx.conf.
sed -i -E 's/^([[:space:]]*)server_tokens[[:space:]][^;]*;/\1server_tokens off;/' /etc/nginx/nginx.conf
grep -qE '^[[:space:]]*server_tokens off;' /etc/nginx/nginx.conf \
  || sed -i -E '0,/^[[:space:]]*http[[:space:]]*\{/s//&\n\tserver_tokens off;/' /etc/nginx/nginx.conf
grep -qE '^[[:space:]]*server_tokens off;' /etc/nginx/nginx.conf \
  || nginx_refused 'nginx.conf has no http block to turn server_tokens off in, it is as it was'
# The security policy and Vite's preload Link headers outgrow nginx's default 4k buffer: a 502.
cat > /etc/nginx/conf.d/eeploi-fastcgi.conf <<'NGINX'
fastcgi_buffer_size 32k;
fastcgi_buffers 16 16k;
NGINX
rm -f /etc/nginx/sites-enabled/default
# The catch-all for unknown hosts refuses the TLS handshake before any HTTP, so it needs no
# certificate: the self-signed one an older release made goes.
install -d -m 755 /etc/nginx/ssl
rm -f /etc/nginx/ssl/catch-all.crt /etc/nginx/ssl/catch-all.key
cat > /etc/nginx/sites-available/catch-all <<'NGINX'
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_reject_handshake on;
}
NGINX
ln -sfn /etc/nginx/sites-available/catch-all /etc/nginx/sites-enabled/catch-all
# A running nginx takes the config now; a stopped one stays stopped.
nginx -t || nginx_refused 'nginx refuses its config, it is as it was'
# D-13: a reload nginx takes, then rejects, isn't caught here.
systemctl try-reload-or-restart nginx || nginx_refused 'nginx did not reload, its config is as it was'
rm -rf "$nginx_prev"

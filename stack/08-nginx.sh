# 8. nginx: room for large headers, no default site, a catch-all that refuses the TLS handshake for
#    unknown hosts; the old config comes back when nginx refuses the new one or doesn't reload
STEP='8. nginx'
# The files this step changes stay aside until nginx takes the new config, and come back if it
# doesn't: a live server keeps serving its sites. A copy left aside by a run that was cut off is the
# old config, so it stays. Every file this step writes or removes is in nginx_files.
nginx_files='/etc/nginx/conf.d/eeploi-fastcgi.conf /etc/nginx/sites-enabled/default
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

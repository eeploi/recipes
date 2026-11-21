# 8. nginx: real visitor IPs from Cloudflare, room for large headers, no default site, a catch-all that
#    refuses the TLS handshake for unknown hosts
STEP='8. nginx'
cat > /etc/nginx/conf.d/cloudflare.conf <<'NGINX'
{real_ip}
real_ip_header CF-Connecting-IP;
NGINX
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
nginx -t

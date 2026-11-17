# 8. nginx: real visitor IPs from Cloudflare, room for large headers, no default site, catch-all for unknown hosts
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
mkdir -p /etc/nginx/ssl
[ -f /etc/nginx/ssl/catch-all.crt ] || openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 3650 \
  -subj "/CN=catch-all" -keyout /etc/nginx/ssl/catch-all.key -out /etc/nginx/ssl/catch-all.crt 2>/dev/null
chmod 600 /etc/nginx/ssl/catch-all.key
cat > /etc/nginx/sites-available/catch-all <<'NGINX'
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_certificate /etc/nginx/ssl/catch-all.crt;
    ssl_certificate_key /etc/nginx/ssl/catch-all.key;
    return 444;
}
NGINX
ln -sfn /etc/nginx/sites-available/catch-all /etc/nginx/sites-enabled/catch-all
nginx -t

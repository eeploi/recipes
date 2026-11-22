# 8. nginx: real visitor IPs from Cloudflare. eeploi fills in Cloudflare's ranges, so this step
#    stays apart from step 8's nginx config, which runs on a live server too.
STEP='8. nginx: real visitor IPs'
cat > /etc/nginx/conf.d/cloudflare.conf <<'NGINX'
{real_ip}
real_ip_header CF-Connecting-IP;
NGINX

# nginx takes the visitor's IP from Cloudflare's header, from Cloudflare's ranges only.
f=/etc/nginx/conf.d/cloudflare.conf
grep -qxF 'real_ip_header CF-Connecting-IP;' "$f" || { echo 'cloudflare.conf: not real_ip_header CF-Connecting-IP' >&2; exit 1; }
grep -qE '^set_real_ip_from [0-9a-f.:]+/[0-9]+;$' "$f" || { echo 'cloudflare.conf: no set_real_ip_from' >&2; exit 1; }
# nginx accepts it.
nginx -t

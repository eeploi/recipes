# 5. Firewall: SSH on the custom port, HTTPS only from Cloudflare, nothing on 80
STEP='5. Firewall'
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'ssh'
# Keep 22 open until the new port is tested, or this session drops before SSH moves.
[ "$SSH_PORT" = 22 ] || ufw allow 22/tcp comment 'ssh, remove after testing the new port'
for range in {ranges}; do ufw allow from "$range" to any port 443 proto tcp comment 'cloudflare'; done
ufw --force enable

# 0. Values: the deploy user, the SSH port and the PHP version in /etc/eeploi/recipes.conf, so a
#    later run of the steps on this server reads them from there. KEY=value, read, never sourced.
STEP='0. Values'
mkdir -p /etc/eeploi
printf '# Written by step 0 of the eeploi recipes. KEY=value, each key once.\nDEPLOY_USER=%s\nSSH_PORT=%s\nPHP=%s\n' "$DEPLOY_USER" "$SSH_PORT" "$PHP" > /etc/eeploi/recipes.conf
chown root:root /etc/eeploi/recipes.conf
chmod 644 /etc/eeploi/recipes.conf

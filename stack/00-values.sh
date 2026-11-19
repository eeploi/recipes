# 0. Values: the deploy user, the SSH port and the PHP version in /etc/eeploi/recipes.conf, so a
#    later run of the steps on this server reads them from there. KEY=value, read, never sourced.
STEP='0. Values'
[ ! -L /etc/eeploi ] || { echo '/etc/eeploi is a link, nothing changed' >&2; exit 1; }
mkdir -p /etc/eeploi
chown root:root /etc/eeploi
chmod 755 /etc/eeploi
RECIPES_CONF_TMP=$(mktemp /etc/eeploi/.recipes.conf.XXXXXX)
printf '# Written by step 0 of the eeploi recipes. KEY=value, each key once.\nDEPLOY_USER=%s\nSSH_PORT=%s\nPHP=%s\n' "$DEPLOY_USER" "$SSH_PORT" "$PHP" > "$RECIPES_CONF_TMP"
chown root:root "$RECIPES_CONF_TMP"
chmod 644 "$RECIPES_CONF_TMP"
mv -f "$RECIPES_CONF_TMP" /etc/eeploi/recipes.conf

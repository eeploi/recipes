# The values file is root's, 0644, in a directory only root may change, and holds DEPLOY_USER,
# SSH_PORT and PHP once each, with nothing else but comments: the user (not root) and the port
# (22 or 10000 to 32767) this server runs with, and a valid PHP version (the default PHP may
# change later).
[ "$(stat -c '%F %U:%G %a' /etc/eeploi)" = 'directory root:root 755' ]
[ "$(stat -c '%F %U:%G %a' /etc/eeploi/recipes.conf)" = 'regular file root:root 644' ]
[ "$(grep -v '^#' /etc/eeploi/recipes.conf | cut -d= -f1 | LC_ALL=C sort | paste -sd' ')" = 'DEPLOY_USER PHP SSH_PORT' ]
grep -qxF "DEPLOY_USER=$DEPLOY_USER" /etc/eeploi/recipes.conf
grep -qxE 'DEPLOY_USER=[a-z][a-z0-9_-]{1,31}' /etc/eeploi/recipes.conf
[ "$DEPLOY_USER" != root ]
grep -qxF "SSH_PORT=$SSH_PORT" /etc/eeploi/recipes.conf
grep -qxE 'SSH_PORT=(22|1[0-9]{4}|2[0-9]{4}|3[01][0-9]{3}|32[0-6][0-9]{2}|327[0-5][0-9]|3276[0-7])' /etc/eeploi/recipes.conf
grep -qxE 'PHP=[0-9]\.[0-9]' /etc/eeploi/recipes.conf

# The values file is root's, 0644 and no link, and holds DEPLOY_USER, SSH_PORT and PHP once each,
# with nothing else but comments: the user and the port this server runs with, and a valid PHP
# version (the default PHP may change later).
[ ! -L /etc/eeploi/recipes.conf ]
[ "$(stat -c '%F %U:%G %a' /etc/eeploi/recipes.conf)" = 'regular file root:root 644' ]
[ "$(grep -v '^#' /etc/eeploi/recipes.conf | cut -d= -f1 | LC_ALL=C sort | paste -sd' ')" = 'DEPLOY_USER PHP SSH_PORT' ]
grep -qxF "DEPLOY_USER=$DEPLOY_USER" /etc/eeploi/recipes.conf
grep -qxF "SSH_PORT=$SSH_PORT" /etc/eeploi/recipes.conf
grep -qxE 'PHP=[0-9]\.[0-9]' /etc/eeploi/recipes.conf

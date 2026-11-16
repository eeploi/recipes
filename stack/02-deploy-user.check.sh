# The deploy user exists, has no password and has eeploi's key; only root and it may use cron and at.
id "$DEPLOY_USER" >/dev/null
passwd -S "$DEPLOY_USER" | awk '{ print $2 }' | grep -qx L
[ -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ]
[ "$(cat /etc/cron.allow)" = "$(printf 'root\n%s' "$DEPLOY_USER")" ]
cmp -s /etc/cron.allow /etc/at.allow

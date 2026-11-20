# logrotate accepts eeploi's file.
logrotate -d /etc/logrotate.d/eeploi 2>/dev/null
# The logs are the deploy user's, and rotate as that user.
grep -qxF "/home/$DEPLOY_USER/.eeploi/*/*.log {" /etc/logrotate.d/eeploi
grep -qxF "    su $DEPLOY_USER $DEPLOY_USER" /etc/logrotate.d/eeploi

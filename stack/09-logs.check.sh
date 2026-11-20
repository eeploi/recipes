# logrotate accepts eeploi's file.
logrotate -d /etc/logrotate.d/eeploi 2>/dev/null
# The logs are the deploy user's, and rotate as that user, and nothing else.
[ "$(grep '{$' /etc/logrotate.d/eeploi)" = "/home/$DEPLOY_USER/.eeploi/*/*.log {" ]
[ "$(grep '^ *su ' /etc/logrotate.d/eeploi)" = "    su $DEPLOY_USER $DEPLOY_USER" ]

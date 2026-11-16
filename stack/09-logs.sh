# 9. Logs: rotate eeploi's worker and scheduler logs, as the deploy user, whose folder they're in
STEP='9. Logs'
cat > /etc/logrotate.d/eeploi <<ROTATE
/home/$DEPLOY_USER/.eeploi/*/*.log {
    su $DEPLOY_USER $DEPLOY_USER
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
ROTATE

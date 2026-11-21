# sshd accepts its config.
sshd -t
# The settings in effect, after every drop-in: no later file turns password login or forwarding
# back on. sshd -T prints each setting once, in lower case.
ssh_settings=$(sshd -T)
[ "$(grep '^port ' <<< "$ssh_settings")" = "port $SSH_PORT" ]
for setting in 'permitrootlogin no' 'passwordauthentication no' 'kbdinteractiveauthentication no' \
  'pubkeyauthentication yes' "allowusers $DEPLOY_USER" 'maxauthtries 3' 'logingracetime 20' \
  'maxstartups 10:30:60' 'x11forwarding no' 'allowagentforwarding no' 'allowtcpforwarding local' 'permittunnel no'; do
  grep -qxF "$setting" <<< "$ssh_settings" || { echo "sshd -T: not $setting" >&2; exit 1; }
done
# Only moduli of 3072 bits and up, and at least one.
awk '$1 !~ /^#/ { n++; if ($5 < 3071) small++ } END { exit !(n && !small) }' /etc/ssh/moduli

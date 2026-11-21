# sshd accepts its config.
sshd -t
# The settings sshd reads, after every drop-in: no later file turns password login or forwarding
# back on, or lets another user in. sshd -T prints each setting in lower case.
ssh_settings=$(sshd -T)
[ "$(grep '^port ' <<< "$ssh_settings")" = "port $SSH_PORT" ]
[ "$(grep '^allowusers ' <<< "$ssh_settings")" = "allowusers $DEPLOY_USER" ]
for setting in 'permitrootlogin no' 'passwordauthentication no' 'kbdinteractiveauthentication no' \
  'pubkeyauthentication yes' 'maxauthtries 3' 'logingracetime 20' 'maxstartups 10:30:60' \
  'x11forwarding no' 'allowagentforwarding no' 'allowtcpforwarding local' 'allowstreamlocalforwarding local' \
  'permittunnel no' 'modulifile /etc/ssh/eeploi-moduli'; do
  grep -qxF "$setting" <<< "$ssh_settings" || { echo "sshd -T: not $setting" >&2; exit 1; }
done
# eeploi's moduli file is root's, 0644, with only groups of 3072 bits and up, and at least one.
[ "$(stat -c '%F %U:%G %a' /etc/ssh/eeploi-moduli)" = 'regular file root:root 644' ]
awk '$1 !~ /^#/ { n++; if ($5 < 3071) small++ } END { exit !(n && !small) }' /etc/ssh/eeploi-moduli

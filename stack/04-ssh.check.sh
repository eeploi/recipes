# sshd accepts its config.
sshd -t
# The settings sshd reads, after every drop-in: no later file turns password login or forwarding
# back on, or lets another user in. sshd -T prints each setting in lower case.
# D-11: sshd -T reads the config on disk, not the running sshd.
ssh_settings=$(sshd -T)
[ "$(grep '^port ' <<< "$ssh_settings")" = "port $SSH_PORT" ]
[ "$(grep '^allowusers ' <<< "$ssh_settings")" = "allowusers $DEPLOY_USER" ]
for setting in 'permitrootlogin no' 'passwordauthentication no' 'kbdinteractiveauthentication no' \
  'pubkeyauthentication yes' 'maxauthtries 3' 'logingracetime 20' 'maxstartups 10:30:60' \
  'x11forwarding no' 'allowagentforwarding no' 'allowtcpforwarding local' 'allowstreamlocalforwarding local' \
  'permittunnel no' 'modulifile /etc/ssh/eeploi-moduli'; do
  grep -qxF "$setting" <<< "$ssh_settings" || { echo "sshd -T: not $setting" >&2; exit 1; }
done
# What sshd offers: the post-quantum key exchange first, no NIST curve key exchange, no SHA-1 MAC,
# no ECDSA host key; the host keys ed25519 and RSA only, the ECDSA key file left as it is.
[ "$(grep '^kexalgorithms ' <<< "$ssh_settings" | cut -d' ' -f2 | cut -d, -f1)" = mlkem768x25519-sha256 ] \
  || { echo 'sshd -T: the first key exchange is not mlkem768x25519-sha256' >&2; exit 1; }
if grep -qE '^kexalgorithms .*ecdh-sha2-nistp' <<< "$ssh_settings" || grep -qE '^macs .*hmac-sha1' <<< "$ssh_settings" \
  || grep -qE '^hostkeyalgorithms .*ecdsa-sha2-nistp' <<< "$ssh_settings"; then
  echo 'sshd -T: a NIST curve or SHA-1 is offered' >&2; exit 1
fi
[ "$(grep '^hostkey ' <<< "$ssh_settings" | paste -sd' ')" = 'hostkey /etc/ssh/ssh_host_ed25519_key hostkey /etc/ssh/ssh_host_rsa_key' ] \
  || { echo 'sshd -T: the host keys are not ed25519 and RSA only' >&2; exit 1; }
ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub >/dev/null
ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub >/dev/null
# eeploi's moduli file is root's, 0644, with only groups of 3072 bits and up, and at least one.
[ "$(stat -c '%F %U:%G %a' /etc/ssh/eeploi-moduli)" = 'regular file root:root 644' ]
awk '$1 !~ /^#/ { n++; if ($5 < 3071) small++ } END { exit !(n && !small) }' /etc/ssh/eeploi-moduli

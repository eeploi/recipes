# 4. SSH: custom port, keys only, no root login, few tries, no forwarding but local (an SSH tunnel to
#    the database), no NIST curves or SHA-1 in what it offers, host keys ed25519 and RSA only (eeploi
#    pins the ed25519 one). 00- sorts first: sshd keeps the first value it reads, so a 50-cloud-init.conf
#    with password login can't win. An old eeploi.conf goes.
STEP='4. SSH'
rm -f /etc/ssh/sshd_config.d/eeploi.conf
# Diffie-Hellman groups of 3072 bits and up only (the moduli file counts 3071), in a file of our
# own: /etc/ssh/moduli is the package's, and a changed one would hold back its security updates.
SSH_MODULI_TMP=$(mktemp /etc/ssh/.eeploi-moduli.XXXXXX)
awk '$1 ~ /^#/ { print; next } $5 >= 3071 { print; n++ } END { exit !n }' /etc/ssh/moduli > "$SSH_MODULI_TMP" \
  || { rm -f "$SSH_MODULI_TMP"; echo 'no moduli of 3072 bits and up in /etc/ssh/moduli, SSH is as it was' >&2; exit 1; }
chmod 644 "$SSH_MODULI_TMP"
mv -f "$SSH_MODULI_TMP" /etc/ssh/eeploi-moduli
cat > /etc/ssh/sshd_config.d/00-eeploi.conf <<SSHD
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers $DEPLOY_USER
MaxAuthTries 3
LoginGraceTime 20
MaxStartups 10:30:60
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding local
AllowStreamLocalForwarding local
PermitTunnel no
ModuliFile /etc/ssh/eeploi-moduli
KexAlgorithms -ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521
MACs -hmac-sha1-etm@openssh.com,hmac-sha1
HostKeyAlgorithms -ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ecdsa-sha2-nistp256-cert-v01@openssh.com,ecdsa-sha2-nistp384-cert-v01@openssh.com,ecdsa-sha2-nistp521-cert-v01@openssh.com
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
SSHD
sshd -t
# Ubuntu's sshd-socket-generator writes ssh.socket's addresses from the Port above, on IPv4 and
# IPv6. Without it, both addresses are written here: a bare port binds IPv6 only, since
# ssh.socket sets BindIPv6Only=ipv6-only.
rm -f /etc/systemd/system/ssh.socket.d/eeploi.conf
if [ ! -x /usr/lib/systemd/system-generators/sshd-socket-generator ] && [ ! -x /lib/systemd/system-generators/sshd-socket-generator ]; then
  mkdir -p /etc/systemd/system/ssh.socket.d
  printf '[Socket]
ListenStream=
ListenStream=0.0.0.0:%s
ListenStream=[::]:%s
' "$SSH_PORT" "$SSH_PORT" > /etc/systemd/system/ssh.socket.d/eeploi.conf
fi

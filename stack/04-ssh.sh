# 4. SSH: custom port, keys only, no root login, few tries, no forwarding but local (an SSH tunnel to
#    the database). 00- sorts first: sshd keeps the first value it reads, so a 50-cloud-init.conf
#    with password login can't win. An old eeploi.conf goes.
STEP='4. SSH'
rm -f /etc/ssh/sshd_config.d/eeploi.conf
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
PermitTunnel no
SSHD
# Diffie-Hellman groups of 3072 bits and up only (the moduli file counts 3071).
SSH_MODULI_TMP=$(mktemp /etc/ssh/.moduli.XXXXXX)
awk '$1 ~ /^#/ || $5 >= 3071' /etc/ssh/moduli > "$SSH_MODULI_TMP"
awk '$1 !~ /^#/ { n++ } END { exit !n }' "$SSH_MODULI_TMP" || { rm -f "$SSH_MODULI_TMP"; echo 'no moduli of 3072 bits and up, /etc/ssh/moduli is as it was' >&2; exit 1; }
chmod 644 "$SSH_MODULI_TMP"
mv -f "$SSH_MODULI_TMP" /etc/ssh/moduli
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

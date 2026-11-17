# 4. SSH: custom port, keys only, no root login. 00- sorts first: sshd keeps the first value it
#    reads, so a 50-cloud-init.conf with password login can't win. An old eeploi.conf goes.
STEP='4. SSH'
rm -f /etc/ssh/sshd_config.d/eeploi.conf
cat > /etc/ssh/sshd_config.d/00-eeploi.conf <<SSHD
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers $DEPLOY_USER
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

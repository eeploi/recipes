# 0. Lock root's password before anything slow. Without the customer's own key Hetzner mails one
#    in plain text; from here on it no longer works. Hetzner's Reset root password, or eeploi's
#    Set a new root password, sets a new one through the guest agent (docs: New server, key+lock).
#    /etc/eeploi/root-locked records that this step locked it, so a password set later is the
#    owner's, not one the provider set.
STEP='0. Lock root password'
passwd -l root
[ ! -L /etc/eeploi ] || { echo '/etc/eeploi is a link, nothing changed' >&2; exit 1; }
mkdir -p /etc/eeploi
chown root:root /etc/eeploi
chmod 755 /etc/eeploi
echo '# Written by step 0 of the eeploi recipes once root'\''s password was locked.' > /etc/eeploi/root-locked
chown root:root /etc/eeploi/root-locked
chmod 644 /etc/eeploi/root-locked

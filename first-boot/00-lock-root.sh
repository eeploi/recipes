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
ROOT_LOCKED_TMP=$(mktemp /etc/eeploi/.root-locked.XXXXXX)
echo '# Written by step 0 of the eeploi recipes once root'\''s password was locked.' > "$ROOT_LOCKED_TMP"
chown root:root "$ROOT_LOCKED_TMP"
chmod 644 "$ROOT_LOCKED_TMP"
mv -f "$ROOT_LOCKED_TMP" /etc/eeploi/root-locked

# 0. Lock root's password before anything slow. Without the customer's own key Hetzner mails one
#    in plain text; from here on it no longer works. Hetzner's Reset root password, or eeploi's
#    Set a new root password, sets a new one through the guest agent (docs: New server, key+lock).
STEP='0. Lock root password'
passwd -l root

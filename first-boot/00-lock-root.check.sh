# Root's password is locked. After the first boot (cloud-init's boot-finished is there), a password
# the owner set (Reset root password, Set a new root password) passes too, with a note: root can't
# log in over SSH (step 4). No password at all never passes.
root=$(passwd -S root | awk '{ print $2 }')
if [ "$root" = P ] && [ -e /var/lib/cloud/instance/boot-finished ]; then
  echo "note: root has a password (set after the first boot); root can't log in over SSH" >&2
else
  [ "$root" = L ] || { echo "root's password is not locked: $root" >&2; exit 1; }
fi

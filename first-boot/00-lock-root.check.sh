# Root's password is locked. Once step 0 has locked it (/etc/eeploi/root-locked, root's), a
# password set later (Reset root password, Set a new root password) passes too, with a note: root
# can't log in over SSH (step 4). No password at all never passes.
root=$(passwd -S root | awk '{ print $2 }')
if [ "$root" = P ] && [ "$(stat -c '%F %U:%G' /etc/eeploi/root-locked 2> /dev/null)" = 'regular file root:root' ]; then
  echo "note: root has a password (set after the first boot); root can't log in over SSH" >&2
else
  [ "$root" = L ] || { echo "root's password is not locked: $root" >&2; exit 1; }
fi

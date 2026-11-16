# Root's password is locked.
passwd -S root | awk '{ print $2 }' | grep -qx L

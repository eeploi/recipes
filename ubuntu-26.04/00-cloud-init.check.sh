# cloud-init-local starts after AppArmor (D-29: canonical/cloud-init#7210): the drop-in is step 0's,
# a file, byte for byte, root's and 0644, and systemd has loaded it.
dropin=/etc/systemd/system/cloud-init-local.service.d/10-after-apparmor.conf
cmp -s "$dropin" <(printf '%s\n' '[Unit]' 'After=apparmor.service') \
  || { echo "$dropin: not the drop-in step 0 writes" >&2; exit 1; }
[ "$(stat -c '%F %U:%G %a' "$dropin")" = 'regular file root:root 644' ] || { echo "$dropin: not a file, root's, 0644" >&2; exit 1; }
# A server without cloud-init has the drop-in only.
[ "$(systemctl show -p LoadState --value cloud-init-local.service)" = not-found ] \
  || case " $(systemctl show -p After --value cloud-init-local.service) " in
    *' apparmor.service '*) ;;
    *) echo 'cloud-init-local.service: not after apparmor.service' >&2; exit 1 ;;
  esac

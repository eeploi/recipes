# cloud-init-local starts after AppArmor (D-29: canonical/cloud-init#7142): the drop-in is step 0's,
# byte for byte, root's and 0644, and systemd has loaded it.
dropin=/etc/systemd/system/cloud-init-local.service.d/10-after-apparmor.conf
cmp -s "$dropin" <(printf '%s\n' '[Unit]' 'After=apparmor.service') \
  || { echo "$dropin: not the drop-in step 0 writes" >&2; exit 1; }
[ "$(stat -c '%U:%G %a' "$dropin")" = 'root:root 644' ] || { echo "$dropin: not root's, 0644" >&2; exit 1; }
case " $(systemctl show -p After --value cloud-init-local.service) " in
  *' apparmor.service '*) ;;
  *) echo 'cloud-init-local.service: not after apparmor.service' >&2; exit 1 ;;
esac

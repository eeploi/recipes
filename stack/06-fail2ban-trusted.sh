# 6. fail2ban: eeploi's own addresses, never banned by any jail. D-22: eeploi fills in the list, so
#    this step stays apart from step 6, which runs on a live server too.
STEP="6. fail2ban: eeploi's addresses"
jail=/etc/fail2ban/jail.d/eeploi-trusted.conf
read -ra trusted <<< '{trusted_ips}'
# D-23: one address each, IPv4 bare or /32, IPv6 bare or /128. An empty list is valid.
python3 -I -c '
import ipaddress, re, sys
for n, a in enumerate(sys.argv[1:], 1):
    m = re.fullmatch(r"([0-9A-Fa-f:.]+)(?:/([0-9]+))?", a)
    try:
        ip = ipaddress.ip_address(m[1]) if m else None
    except ValueError:
        ip = None
    if ip is None or m[2] not in (None, str(ip.max_prefixlen)):
        sys.exit("address %d is not one IPv4 or IPv6 address, nothing changed" % n)' ${trusted[@]+"${trusted[@]}"}
# The old file stays aside until fail2ban accepts the new one, and comes back if it doesn't. One
# left aside by a run that was cut off is that old file, so it stays.
[ -f "$jail.prev" ] || [ ! -f "$jail" ] || cp -a "$jail" "$jail.prev"
# Added to what fail2ban already ignores, under [DEFAULT], so every jail ignores them, recidive
# too. Another list in a file of its own adds itself the same way.
printf '[DEFAULT]\nignoreip = %%(known/ignoreip)s%s\n' "${trusted[*]:+ ${trusted[*]}}" > "$jail"
chmod 644 "$jail"
if ! fail2ban-client -t; then
  if [ -f "$jail.prev" ]; then mv -f "$jail.prev" "$jail"; else rm -f "$jail"; fi
  echo "fail2ban refuses its config, eeploi's addresses are as they were" >&2
  exit 1
fi
rm -f "$jail.prev"
# A live server takes the list now; a stopped fail2ban stays stopped. D-24: a live server runs this
# step only by hand.
systemctl try-reload-or-restart fail2ban

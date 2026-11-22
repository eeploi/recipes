# 6. fail2ban: eeploi's own addresses, never banned by any jail. D-22: eeploi fills in the list, so
#    this step stays apart from step 6, which runs on a live server too.
STEP="6. fail2ban: eeploi's addresses"
jail=/etc/fail2ban/jail.d/eeploi-trusted.conf
read -ra trusted <<< '{trusted_ips}'
# D-23: one address each, IPv4 bare or /32, IPv6 bare or /128, no IPv4 written as IPv6. An empty
# list is valid.
python3 -I -c '
import ipaddress, re, sys
for n, a in enumerate(sys.argv[1:], 1):
    m = re.fullmatch(r"([0-9A-Fa-f:.]+)(?:/([0-9]+))?", a)
    try:
        ip = ipaddress.ip_address(m[1]) if m else None
    except ValueError:
        ip = None
    if ip is None or m[2] not in (None, str(ip.max_prefixlen)) or getattr(ip, "ipv4_mapped", None):
        sys.exit("address %d is not one IPv4 or IPv6 address, nothing changed" % n)' ${trusted[@]+"${trusted[@]}"}
# The old file stays aside until fail2ban accepts the new one, and comes back if it doesn't. One
# left aside by a run that was cut off is that old file, so it stays.
[ -f "$jail.prev" ] || [ ! -f "$jail" ] || cp -a "$jail" "$jail.prev"
# Under [DEFAULT], so every jail ignores them, recidive too: localhost, as fail2ban's own default,
# then the list. Another list in a file of its own adds itself with %(known/ignoreip)s. Written
# aside and moved in, so a run cut off leaves no half file, and a link is replaced, not followed.
printf '[DEFAULT]\nignoreip = 127.0.0.1/8 ::1%s\n' "${trusted[*]:+ ${trusted[*]}}" > "$jail.new"
chmod 644 "$jail.new"
mv -f "$jail.new" "$jail"
if ! fail2ban-client -t; then
  if [ -f "$jail.prev" ]; then mv -f "$jail.prev" "$jail"; else rm -f "$jail"; fi
  echo "fail2ban refuses its config, eeploi's addresses are as they were" >&2
  exit 1
fi
rm -f "$jail.prev"
# A live server takes the list now; a stopped fail2ban stays stopped. D-24: recipe-run doesn't run
# this step.
systemctl try-reload-or-restart fail2ban

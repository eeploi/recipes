# eeploi's own addresses: the file the step writes, one address each, ignored by every jail.
f=/etc/fail2ban/jail.d/eeploi-trusted.conf
if [ ! -f "$f" ] || [ -L "$f" ]; then echo 'eeploi-trusted.conf: not there' >&2; exit 1; fi
[ "$(stat -c '%U:%G %a' "$f")" = 'root:root 644' ] || { echo 'eeploi-trusted.conf: not root:root 644' >&2; exit 1; }
# The file is the one the step writes: [DEFAULT], and the addresses added to what fail2ban ignores.
line=$(sed -n 2p "$f")
read -ra trusted <<< "${line#'ignoreip = %(known/ignoreip)s'}"
[ "$(cat "$f")" = "$(printf '[DEFAULT]\nignoreip = %%(known/ignoreip)s%s' "${trusted[*]:+ ${trusted[*]}}")" ] \
  || { echo 'eeploi-trusted.conf: not the file the step writes' >&2; exit 1; }
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
        sys.exit("eeploi-trusted.conf: address %d is not one IPv4 or IPv6 address" % n)' ${trusted[@]+"${trusted[@]}"}
# fail2ban accepts its config, and no old file is left aside.
fail2ban-client -t > /dev/null
[ ! -e "$f.prev" ] || { echo 'eeploi-trusted.conf: an old file is left aside' >&2; exit 1; }
# A running fail2ban ignores every address in every jail it runs.
if systemctl is-active --quiet fail2ban; then
  list=$(fail2ban-client status | sed -n 's/.*Jail list:[[:space:]]*//p')
  IFS=', ' read -ra jails <<< "$list"
  for jail in ${jails[@]+"${jails[@]}"}; do
    [[ $jail =~ ^[A-Za-z0-9_.-]+$ ]] || continue
    fail2ban-client get "$jail" ignoreip | python3 -I -c '
import ipaddress, sys
have = set()
for line in sys.stdin:
    if line[:3] in ("|- ", "`- "):
        try:
            have.add(ipaddress.ip_network(line[3:].strip(), strict=False))
        except ValueError:
            pass
for n, a in enumerate(sys.argv[2:], 1):
    if ipaddress.ip_network(a) not in have:
        sys.exit("fail2ban: jail %s does not ignore address %d of eeploi-trusted.conf" % (sys.argv[1], n))' "$jail" ${trusted[@]+"${trusted[@]}"}
  done
fi

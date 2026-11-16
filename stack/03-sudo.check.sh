# The helper is in place, owned by root, and the sudo rule passes visudo.
[ "$(stat -c '%U %a' /usr/local/sbin/eeploi-helper)" = 'root 755' ]
[ -f /etc/eeploi/helper.conf ]
visudo -cqf /etc/sudoers.d/eeploi

# The first boot installed every update waiting: its record is there, root's.
[ "$(stat -c '%F %U:%G' /etc/eeploi/updated)" = 'regular file root:root' ] \
  || { echo 'the first boot installed no updates' >&2; exit 1; }

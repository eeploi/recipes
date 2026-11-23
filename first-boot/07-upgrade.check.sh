# The first boot installed every update waiting: step 7's record is there, root's.
record=/etc/eeploi/updated
[ -f "$record" ] && [ ! -L "$record" ] && [ "$(stat -c %U:%G "$record")" = root:root ] \
  || { echo 'the first boot installed no updates' >&2; exit 1; }

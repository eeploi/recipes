# cloud-init runs this without HOME, and Composer's installer refuses to run without it.
export HOME=/root COMPOSER_HOME=/root/.config/composer

# A step that fails tells eeploi which one, once, so eeploi doesn't wait for a report that never
# comes. Only the step name and the last line the failing step printed go out (what failed, such
# as a host or a package), never the rest of the output, and never a known harmless notice. All
# output still reaches cloud-init's log as well.
REPORT_URL={report_url}
# A report to eeploi tries every 30 seconds until eeploi takes it (2xx) or refuses it (a 3xx, or
# any other 4xx than 408 and 429: the link has expired or was used), and stops 30 minutes after
# the script started, about when eeploi's own window ends. Each try prints its number and HTTP code, never the URL.
REPORT_EVERY=30
REPORT_FOR=1800
report() {
  local try=0 code rc
  while :; do
    try=$((try + 1))
    # The code is that of the last status line in the headers, none without an answer. Its first
    # three characters only, as a status line without a reason phrase ends in a CR.
    code=$(curl -s -o /dev/null -D - --max-time 20 "$@" "$REPORT_URL" | awk '/^HTTP\//{ c = substr($2, 1, 3) } END { print c }') && rc=0 || rc=$?
    echo "Report: try $try, HTTP ${code:-none}, curl $rc"
    case "$code" in
      2??) return 0 ;;
      408 | 429) ;;
      3?? | 4??) return 1 ;;
    esac
    [ $((SECONDS + REPORT_EVERY)) -lt "$REPORT_FOR" ] || return 1
    sleep "$REPORT_EVERY"
  done
}
STEP='Start'
SEEN=''
OUTPUT=$(mktemp)
exec > >(tee -a "$OUTPUT") 2> >(tee -a "$OUTPUT" >&2)
# Each step starts with an empty output file, so the line reported is the failing step's own.
trap '[ "$STEP" = "$SEEN" ] || { SEEN=$STEP; : > "$OUTPUT"; }' DEBUG
report_failure() {
  local line
  sleep 1
  line=$(grep -v -E '^[[:space:]]*$|needrestart|outdated (hypervisor|binaries)|^Scanning (processes|candidates|linux images)|^Running kernel seems to be up-to-date|^No (services|containers) need to be restarted' "$OUTPUT" | tail -n 1 | tr -d '\000-\010\013-\037\177') || true
  if [ "${#line}" -gt 300 ]; then
    line="${line:0:300}"
    line="${line% *} ..."
  fi
  report --data-urlencode "failed=$STEP" --data-urlencode "error=$line" || true
}
trap '[ $? -eq 0 ] || report_failure' EXIT

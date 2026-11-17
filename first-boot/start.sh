# cloud-init runs this without HOME, and Composer's installer refuses to run without it.
export HOME=/root COMPOSER_HOME=/root/.config/composer

# A step that fails tells eeploi which one, once, so eeploi doesn't wait for a report that never
# comes. Only the step name and the last line the failing step printed go out (what failed, such
# as a host or a package), never the rest of the output, and never a known harmless notice. All
# output still reaches cloud-init's log as well.
REPORT_URL={report_url}
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
  curl -fsS --max-time 20 --retry 3 --retry-all-errors --data-urlencode "failed=$STEP" --data-urlencode "error=$line" "$REPORT_URL" || true
}
trap '[ $? -eq 0 ] || report_failure' EXIT

#!/usr/bin/env bash
# Runs report() from first-boot/start.sh against a fake eeploi on localhost, with a try every
# second and a short cap: taken at once, taken after failures, refused at once, the cap with eeploi
# down and with no connection at all. The URL's token never shows in the output. For CI.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
server=''
trap '[ -z "$server" ] || kill "$server" 2> /dev/null; rm -rf "$tmp"' EXIT

# The fake eeploi answers each POST with the next code in $tmp/codes, then with the last one, and
# writes each request body to $tmp/bodies.
cat > "$tmp/server.py" <<'PY'
import http.server, sys
codes_file, bodies_file, port_file = sys.argv[1:4]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        with open(bodies_file, 'ab') as f:
            f.write(body + b'\n')
        with open(codes_file) as f:
            codes = f.read().split()
        code = codes.pop(0) if len(codes) > 1 else codes[0]
        with open(codes_file, 'w') as f:
            f.write(' '.join(codes))
        self.send_response(int(code))
        self.send_header('Content-Length', '0')
        self.end_headers()
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
with open(port_file, 'w') as f:
    f.write(str(server.server_port))
server.serve_forever()
PY
python3 "$tmp/server.py" "$tmp/codes" "$tmp/bodies" "$tmp/port" &
server=$!
for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
port=$(cat "$tmp/port")

# report() as the server runs it, from the rendered first boot.
report=$(bin/render.sh | sed -n '/^report() {$/,/^}$/p')

fail=0
# case_ NAME CODES CAP EXPECT MIN MAX UP: with a cap of CAP seconds, report() exits EXPECT (0 or
# 1) after MIN to MAX tries. The cap counts whole seconds, so it allows one try more or less. UP
# is 1 when the fake eeploi listens, so it must have got the report on each try.
case_() {
  local name=$1 codes=$2 cap=$3 expect=$4 min=$5 max=$6 up=$7 rc tries
  echo "$codes" > "$tmp/codes"
  : > "$tmp/bodies"
  bash -c "
    set -euo pipefail
    REPORT_URL='http://127.0.0.1:$port/report/secret-token?signature=secret-signature'
    $report
    REPORT_EVERY=1 REPORT_FOR=$cap
    report --data-urlencode 'host_keys=ssh-ed25519 AAAA'
  " > "$tmp/out" 2>&1 && rc=0 || rc=$?
  sed 's/^/  /' "$tmp/out"
  tries=$(grep -c '^Report: try ' "$tmp/out" || true)
  if [ "$rc" -ne "$expect" ]; then
    echo "$name: exit $rc, not $expect"
    fail=1
  elif [ "$tries" -lt "$min" ] || [ "$tries" -gt "$max" ]; then
    echo "$name: $tries tries, not $min to $max"
    fail=1
  elif grep -q secret "$tmp/out"; then
    echo "$name: the token is in the output"
    fail=1
  elif [ "$up" -eq 1 ] && [ "$(grep -cx 'host_keys=ssh-ed25519+AAAA' "$tmp/bodies")" -ne "$tries" ]; then
    echo "$name: eeploi did not get the report on each try"
    fail=1
  else
    echo "$name: ok"
  fi
}

case_ 'taken at once' 200 30 0 1 1 1
case_ 'taken after failures' '503 530 408 429 500 204' 30 0 6 6 1
case_ 'refused at once' 410 30 1 1 1 1
case_ 'eeploi down, the cap' 503 4 1 3 5 1
# A port nothing listens on: the fake eeploi's, once it is stopped.
kill "$server"
wait "$server" 2> /dev/null || true
server=''
case_ 'no connection, the cap' 200 4 1 3 5 0

exit "$fail"

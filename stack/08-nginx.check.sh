# The catch-all for unknown hosts is on, the default server for 443 on IPv4 and IPv6, refuses the
# TLS handshake, and has no certificate of its own, nor the one an older release made.
[ "$(readlink /etc/nginx/sites-enabled/catch-all)" = /etc/nginx/sites-available/catch-all ] || { echo 'the catch-all is off' >&2; exit 1; }
grep -qx '    listen 443 ssl default_server;' /etc/nginx/sites-available/catch-all || { echo 'the catch-all is not the IPv4 default' >&2; exit 1; }
grep -qxF '    listen [::]:443 ssl default_server;' /etc/nginx/sites-available/catch-all || { echo 'the catch-all is not the IPv6 default' >&2; exit 1; }
grep -qx '    ssl_reject_handshake on;' /etc/nginx/sites-available/catch-all || { echo 'the catch-all does not refuse the handshake' >&2; exit 1; }
if grep -q 'ssl_certificate' /etc/nginx/sites-available/catch-all || [ -e /etc/nginx/ssl/catch-all.key ] || [ -e /etc/nginx/ssl/catch-all.crt ]; then
  echo 'the catch-all still has a certificate' >&2; exit 1
fi
[ -d /etc/nginx/ssl ]
# No old config left aside: a run that was cut off leaves one.
[ ! -e /etc/nginx/eeploi.prev ] || { echo 'an old nginx config is left aside (/etc/nginx/eeploi.prev)' >&2; exit 1; }
# No nginx version in a header or an error page: nginx.conf turns server_tokens off in http {},
# and no file nginx reads turns it on again, in any block. nginx takes on, build and any case
# (ngx_strcasecmp), so anything but off fails. D-27: the line is in Ubuntu's nginx.conf, which an
# nginx update keeps.
# nginx reader, begin. D-28: the same bytes in every file that holds it, from this line to its
# end line (bin/check-layout.sh).
# nginx_read DIRECTIVE...: reads nginx -T on stdin as nginx reads it (ngx_conf_read_token): a word
# starts at a character that is not a space, and a quote, # or { } ; is special only where a word
# starts. Inside a word they are plain, so a}#" is one word; a quoted string is one word; \ takes
# the next character as it is; ${ stays in a word. So a ; or a directive's name inside quotes, a
# word or a comment is never taken for one, and a directive may span lines.
# Prints, in the order nginx -T prints them: file <path> where each file starts; server <n> file
# <path> for each server block in http or stream, n counting them; and for each of the directives
# named, where it is and its arguments: http <name> <args>, server <n> <name> <args> (in that
# server block itself), or other <name> <args> (in any other block). An empty argument shows as "".
# nginx -T prints each file on its own, an included one after the file that includes it, so each
# starts at the top: a directive at the top of a file is taken as an http one. Limit: so is one
# from a file included inside a server block, such as a snippet.
# Fails closed: the lines are printed only at the end, and none if the reading went out of step
# with nginx's (a file that doesn't end where nginx -T says the next begins, a quote left open)
# or a value printed holds a line break or is too long.
nginx_read() {
  # shellcheck disable=SC2016 # awk's $
  awk -v dirs=" $* " '
  function word() { if (inword) { args[n++] = tok }; tok = ""; inword = 0; var = 0 }
  function emit(prefix,   i, a, s) {
    s = prefix " " args[0]
    for (i = 1; i < n; i++) {
      a = args[i]
      if (a ~ /[[:cntrl:]]/ || length(a) > 1000) bad = 1
      s = s " " (a == "" ? "\"\"" : a)
    }
    out[lines++] = s
  }
  function directive() {
    if (n > 0 && index(dirs, " " args[0] " ")) {
      if (stack[depth] == "server" && id[depth]) emit("server " id[depth])
      else if (depth == 0 || (depth == 1 && stack[1] == "http")) emit("http")
      else emit("other")
    }
    n = 0
  }
  function block_start() {
    depth++
    stack[depth] = n > 0 ? args[0] : ""
    id[depth] = 0
    if (stack[depth] == "server" && (depth == 1 || stack[depth - 1] == "http" || stack[depth - 1] == "stream")) {
      servers++; id[depth] = servers; out[lines++] = "server " servers " file " file
    }
    n = 0
  }
  function block_end() { if (n > 0 || depth == 0) bad = 1; n = 0; if (depth > 0) depth-- }
  function clean() { return q == "" && !inword && !esc && n == 0 && depth == 0 }
  BEGIN { depth = 0; n = 0; tok = ""; inword = 0; var = 0; esc = 0; q = ""; file = "-"; lines = 0; bad = 0 }
  q == "" && !inword && /^# configuration file .*:$/ {
    # Where nginx -T starts a file, the one before has ended: a block or directive still open there
    # means this reading is out of step with nginx, or the line is in a file of its own.
    if (!clean()) bad = 1
    file = substr($0, 22, length($0) - 22)
    if (file ~ /[[:cntrl:]]/) bad = 1
    out[lines++] = "file " file
    next
  }
  {
    line = $0 "\n"
    len = length(line)
    for (i = 1; i <= len; i++) {
      c = substr(line, i, 1)
      if (esc) { tok = tok c; esc = 0; continue }
      if (q != "") {
        if (c == "\\") esc = 1
        else if (c == q) { q = ""; word() }
        else tok = tok c
        continue
      }
      if (!inword) {
        if (c == " " || c == "\t" || c == "\r" || c == "\n") continue
        if (c == ";") { directive(); continue }
        if (c == "{") { block_start(); continue }
        if (c == "}") { block_end(); continue }
        if (c == "#") break
        inword = 1
        if (c == "\"" || c == "\047") { q = c; continue }
        if (c == "\\") { esc = 1; continue }
        if (c == "$") var = 1
        tok = tok c
        continue
      }
      if (c == "{" && var) { tok = tok c; continue }
      var = 0
      if (c == " " || c == "\t" || c == "\r" || c == "\n") { word(); continue }
      if (c == ";") { word(); directive(); continue }
      if (c == "{") { word(); block_start(); continue }
      if (c == "\\") { esc = 1; continue }
      if (c == "$") var = 1
      tok = tok c
    }
  }
  END {
    if (bad || !clean()) exit 1
    for (i = 0; i < lines; i++) print out[i]
  }'
}
# nginx reader, end.
# nginx accepts its config: nginx -T tests it before it prints it. When it doesn't, nginx -t says
# why. D-11: nginx -T reads the config on disk.
config=$(nginx -T 2> /dev/null) || { echo 'nginx refuses its config' >&2; nginx -t || true; exit 1; }
tokens=$(nginx_read server_tokens <<< "$config") || { echo 'nginx -T could not be read as nginx reads it' >&2; exit 1; }
# Exit 3: no off in http {} of nginx.conf, the first file nginx -T prints (a comment that looks
# like a file's start can't stand in for it); 4: a value but off.
rc=0
# shellcheck disable=SC2016 # awk's $
awk '$1 == "file" { files++; f = files == 1 ? substr($0, 6) : ""; next } NF == 0 || ($1 == "server" && $3 == "file") { next }
  { v = tolower($0); sub(/^[a-z]+( [0-9]+)? server_tokens /, "", v) }
  v != "off" { on = 1 } f == "/etc/nginx/nginx.conf" && $1 == "http" && v == "off" { ok = 1 }
  END { exit (!ok ? 3 : (on ? 4 : 0)) }' <<< "$tokens" || rc=$?
case "$rc" in
  0) ;;
  3) echo 'nginx.conf does not turn server_tokens off' >&2; exit 1 ;;
  4) echo 'nginx turns server_tokens on again' >&2; exit 1 ;;
  *) echo "server_tokens could not be read (awk exit $rc)" >&2; exit 1 ;;
esac

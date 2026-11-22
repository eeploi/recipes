#!/usr/bin/env bash
# Probe: nginx. The config nginx reads, after every include (nginx -T), cut to these directives:
# per server block its listens and server names and whether it refuses the TLS handshake, and a
# few http settings. Never a certificate, a key or any other directive. And whether a newer stock
# nginx.conf waits next to the one in use (D-27). No nginx: no lines. PROBES.md.
# Lines: server <n> file <path>, server <n> <directive> <arguments>, http <directive> <arguments>,
# nginx-conf-dpkg-dist yes|no; n counts the server blocks in the order nginx -T prints them.
set -euo pipefail
# The directives shown, and the settings whose values are safe to show: in a server block, and in http.
server_safe=(listen server_name ssl_reject_handshake)
http_safe=(server_tokens fastcgi_buffer_size fastcgi_buffers real_ip_header set_real_ip_from)
[ "${1:-}" != --safe ] || { printf '%s\n' "${server_safe[@]}" "${http_safe[@]}"; exit 0; }

command -v nginx > /dev/null || exit 0
# D-17: nginx -T reads the config on disk, not the running nginx.
config=$(nginx -T 2> /dev/null)
# nginx reader, begin. D-28: the same bytes in stack/08-nginx.probe.sh and stack/08-nginx.check.sh,
# from this line to its end line (bin/check-layout.sh).
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
# The lines of this probe: per server block its file and the server directives above, and the http
# settings above. Not the file lines, nor a directive in any other block.
lines=$(nginx_read "${server_safe[@]}" "${http_safe[@]}" <<< "$config")
awk -v server_dirs=" ${server_safe[*]} " -v http_dirs=" ${http_safe[*]} " '
  $1 == "server" && ($3 == "file" || index(server_dirs, " " $3 " ")) { print; next }
  $1 == "http" && index(http_dirs, " " $2 " ")' <<< "$lines"
# D-27: an nginx update that brings a new nginx.conf leaves it as nginx.conf.dpkg-dist.
if [ -e /etc/nginx/nginx.conf.dpkg-dist ]; then echo 'nginx-conf-dpkg-dist yes'; else echo 'nginx-conf-dpkg-dist no'; fi
